require 'minitest'
require 'open3'
require 'pty'

# Every process a test starts is waited for or killed before the next test.
# A child whose test hung or whose runner was interrupted used to outlive the
# run: one orphaned `h save` spun for hours. Three guards:
#   - Open3 block forms (capture2/2e/3, popen2/2e/3) and PTY.spawn kill the
#     child's process tree after LIMIT seconds and then fail the test;
#   - after each test, descendants still alive after a short grace are killed
#     and the test fails, naming them;
#   - when the run ends, even by Ctrl-C, any remaining descendant is killed.
module ChildGuard
  LIMIT = Float(ENV.fetch('HIIRO_TEST_CHILD_LIMIT', '300'))
  GRACE = 3

  class Overrun < StandardError; end

  # [[pid, command], ...] for live (non-zombie) descendants of root.
  def self.descendants(root = Process.pid)
    ps_pid, listing = IO.popen(['/bin/ps', '-A', '-o', 'pid=,ppid=,stat=,command=']) { |io| [io.pid, io.read] }
    rows = listing.lines.map { |line| line.strip.split(/\s+/, 4) }
    found = []
    frontier = [root]
    until frontier.empty?
      parent = frontier.shift
      rows.each do |pid, ppid, stat, command|
        next unless ppid.to_i == parent && pid.to_i != ps_pid

        frontier << pid.to_i
        found << [pid.to_i, command.to_s] unless stat.to_s.start_with?('Z')
      end
    end
    found
  end

  def self.kill_tree(pid)
    pids = [pid, *descendants(pid).map(&:first)]
    pids.each { |each| Process.kill('KILL', each) rescue nil }
  end

  def self.sweep(grace: GRACE)
    deadline = Time.now + grace
    left = descendants
    while left.any? && Time.now < deadline
      sleep 0.05
      left = descendants
    end
    left.each { |pid, _| Process.kill('KILL', pid) rescue nil }
    left.each { |pid, _| Process.wait(pid, Process::WNOHANG) rescue nil }
    left
  end

  # Runs block while a watchdog kills pid's tree after LIMIT seconds.
  def self.watch(pid, what)
    fired = false
    watchdog = Thread.new do
      sleep LIMIT
      fired = true
      kill_tree(pid)
    end
    result = yield
    raise Overrun, "#{what} still running after #{LIMIT.to_i}s; killed" if fired

    result
  ensure
    watchdog&.kill
  end

  module Open3Watch
    %i[popen3 popen2 popen2e].each do |name|
      define_method(name) do |*cmd, &block|
        return super(*cmd) unless block

        super(*cmd) do |*io|
          ChildGuard.watch(io.last.pid, cmd.reject { |arg| arg.is_a?(Hash) }.first(4).join(' ')) { block.call(*io) }
        end
      end
    end
  end

  module PTYWatch
    def spawn(*cmd, &block)
      return super unless block

      super(*cmd) do |reader, writer, pid|
        begin
          ChildGuard.watch(pid, cmd.reject { |arg| arg.is_a?(Hash) }.first(4).join(' ')) { block.call(reader, writer, pid) }
        ensure
          unless (Process.wait(pid, Process::WNOHANG) rescue true)
            ChildGuard.kill_tree(pid)
            Process.wait(pid) rescue nil
          end
        end
      end
    end
  end

  module TestHook
    def after_teardown
      super
      left = ChildGuard.sweep
      flunk "left child processes running (killed): #{left.map { |pid, cmd| "#{pid} #{cmd}" }.join('; ')}" if left.any?
    end
  end

  Open3.singleton_class.prepend(Open3Watch)
  PTY.singleton_class.prepend(PTYWatch)
  Minitest::Test.prepend(TestHook)

  # Registered while the at_exit that runs the tests is executing, so it runs
  # after the run finishes, including one ended by Ctrl-C.
  module ExitSweep
    def before_setup
      unless ChildGuard.instance_variable_get(:@exit_sweep)
        ChildGuard.instance_variable_set(:@exit_sweep, true)
        at_exit { ChildGuard.sweep(grace: 0) }
      end
      super
    end
  end
  Minitest::Test.prepend(ExitSweep)
end
