require "test_helper"
require "open3"
require "rbconfig"

# Runs a throwaway suite that hangs on one child and leaks another, and checks
# that both are killed and reported instead of outliving the run.
class ChildGuardTest < Minitest::Test
  SUITE = <<~'RUBY'
    require "test_helper"
    class Leaky < Minitest::Test
      def test_a_hung_capture
        Open3.capture3("/bin/sleep", "60")
      end

      def test_b_leaked_spawn
        File.write(ENV.fetch("LEAK_PID"), Process.spawn("/bin/sleep", "61").to_s)
      end
    end
  RUBY

  def test_hung_and_leaked_children_are_killed_and_named
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "leaky_test.rb"), SUITE)
      leak_pid = File.join(dir, "leak.pid")
      env = { "HIIRO_TEST_CHILD_LIMIT" => "1", "LEAK_PID" => leak_pid, "HOME" => dir }
      started = Time.now
      out, _, status = Open3.capture3(env, RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-I", __dir__,
                                      File.join(dir, "leaky_test.rb"), "--seed", "1")

      assert_operator Time.now - started, :<, 30
      assert_equal 1, status.exitstatus
      assert_includes out, "ChildGuard::Overrun: /bin/sleep 60 still running after 1s; killed"
      pid = File.read(leak_pid).to_i
      assert_includes out, "left child processes running (killed): #{pid} /bin/sleep 61"
      assert_includes out, "2 runs, 1 assertions, 1 failures, 1 errors"
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    end
  end
end
