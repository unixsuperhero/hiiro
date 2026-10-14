require 'test_helper'
require 'open3'

class OwnedRunTest < Minitest::Test
  include OwnedRunHelpers

  def setup
    @dir = File.realpath(Dir.mktmpdir('owned-run-'))
    @store = run_store(@dir)
    @launcher = Hiiro::OwnedRun::Launcher.new(store: @store, start_timeout: 10)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def request(*argv, cwd: @dir, **opts)
    Hiiro::OwnedRun::LaunchRequest.new(owner: { kind: 'test' },
      command: Hiiro::CommandSpecification.new(*argv, cwd: cwd), placement: { kind: 'detached' }, **opts)
  end

  def test_state_machine_allows_only_forward_transitions
    run = Hiiro::OwnedRun.allocate(request('true'))
    assert_equal 'allocated', run.state
    assert_raises(Hiiro::OwnedRun::InvalidTransition) { run.ready }
    run.start(Hiiro::OwnedRun::ProcessIdentity.new(pid: 42, started: 'x'))
    assert_equal 'started', run.state
    assert_equal 'started pid 42', run.summary
    run.ready
    run.finish(Hiiro::ProcessOutcome.new(exit_code: 0))
    assert_equal 'completed', run.state
    assert_equal 'completed exit 0', run.summary
    assert_raises(Hiiro::OwnedRun::InvalidTransition) { run.fail('late') }
    assert_equal %w[allocated started ready completed], run.times.keys
  end

  def test_signal_death_is_failed_not_exit_zero
    run = Hiiro::OwnedRun.allocate(request('true'))
    run.start(Hiiro::OwnedRun::ProcessIdentity.new(pid: 42, started: 'x'))
    run.finish(Hiiro::ProcessOutcome.new(signal: 'TERM'))
    assert_equal 'failed', run.state
    assert_equal 'failed signal TERM', run.summary
    assert_equal 143, run.outcome.shell_code
  end

  def test_detached_runs_record_actual_exit_status
    ok = @launcher.detached(request('/bin/sh', '-c', 'echo done > out'))
    assert_includes %w[started completed], ok.state
    assert_equal 'completed exit 0', wait_for_run(@store, ok.id).summary
    assert_equal "done\n", File.read(File.join(@dir, 'out'))

    bad = @launcher.detached(request('/bin/sh', '-c', 'exit 7'))
    assert_equal 'failed exit 7', wait_for_run(@store, bad.id).summary
  end

  def test_a_detached_child_never_holds_the_callers_output_open
    gate = File.join(@dir, 'gate')
    code = <<~RUBY
      require 'hiiro'
      launcher = Hiiro::OwnedRun::Launcher.new(store: Hiiro::OwnedRun::Store.new(#{File.join(@dir, 'runs').inspect}))
      request = Hiiro::OwnedRun::LaunchRequest.new(owner: { kind: 'test' }, placement: { kind: 'detached' },
        command: Hiiro::CommandSpecification.new('/bin/sh', '-c', 'echo to-log; echo err-log >&2; while [ ! -f gate ]; do sleep 0.05; done', cwd: #{@dir.inspect}))
      puts launcher.detached(request).id
    RUBY
    started = Time.now
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../../lib', __dir__), '-e', code)
    assert status.success?, err
    assert_operator Time.now - started, :<, 15
    id = out.chomp
    log = File.join(@dir, 'runs', "#{id}.log")
    deadline = Time.now + 10
    sleep 0.05 until (File.exist?(log) && File.read(log).lines.size == 2) || Time.now > deadline
    assert_equal ["err-log\n", "to-log\n"], File.readlines(log).sort
    assert_equal 'started', @store.find(id).state
  ensure
    File.write(gate, '') if gate
    wait_for_run(@store, id) if id
  end

  def test_missing_directory_fails_without_starting_the_command
    marker = File.join(@dir, 'started')
    error = assert_raises(Hiiro::OwnedRun::LaunchError) do
      @launcher.detached(request('/usr/bin/touch', marker, cwd: File.join(@dir, 'gone')))
    end
    assert_equal 'failed', error.run.state
    assert_match(/No such file or directory/, error.run.error)
    refute File.exist?(marker)
    assert_nil error.run.process
  end

  def test_supervisor_refuses_a_run_that_is_no_longer_allocated
    run = @store.create(Hiiro::OwnedRun.allocate(request('/usr/bin/touch', File.join(@dir, 'late'))))
    @store.update(run.id) { |record| record.fail('start not observed within 0s') }
    status = Hiiro::OwnedRun::Supervisor.new(@store, run.id).run
    assert_equal 127, status
    refute File.exist?(File.join(@dir, 'late'))
    assert_equal 'failed: start not observed within 0s', @store.find(run.id).summary
  end

  def test_ready_comes_only_from_the_configured_probe
    flag = File.join(@dir, 'ready-flag')
    gate = File.join(@dir, 'gate')
    probe = Hiiro::CommandSpecification.shell("test -f #{flag.shellescape}", cwd: @dir)
    run = @launcher.detached(request('/bin/sh', '-c', "touch #{flag.shellescape}; while [ ! -f #{gate.shellescape} ]; do sleep 0.02; done", ready: probe))
    deadline = Time.now + 10
    sleep 0.02 until @store.find(run.id).state == 'ready' || Time.now > deadline
    assert_equal 'ready', @store.find(run.id).state
    File.write(gate, '')
    assert_equal 'completed exit 0', wait_for_run(@store, run.id).summary

    plain = @launcher.detached(request('/bin/sh', '-c', 'exit 0'))
    finished = wait_for_run(@store, plain.id)
    refute finished.times.key?('ready')
  end

  def test_process_identity_rejects_a_reused_pid
    identity = Hiiro::OwnedRun::ProcessIdentity.of(Process.pid)
    assert identity.alive?
    reused = Hiiro::OwnedRun::ProcessIdentity.new(pid: Process.pid, started: 'Thu Jan  1 00:00:00 1970')
    refute reused.alive?
  end

  def test_undelivered_pane_command_is_a_failed_launch
    terminal = FakeHerdrTerminal.new
    terminal.deliver = false
    launcher = Hiiro::OwnedRun::Launcher.new(store: @store, herdr: Hiiro::Herdr.new(executor: terminal))
    location = Hiiro::Herdr::Location.new(workspace_id: 'w1', tab_id: 'w1:t1', pane_id: 'w1:p1')
    error = assert_raises(Hiiro::OwnedRun::LaunchError) { launcher.herdr_pane(request('true'), location) }
    assert_equal 'failed: Herdr did not run the command in pane w1:p1', error.run.summary
  end
end
