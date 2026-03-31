require 'test_helper'

class TestHarnessEffectsTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.new
    @harness.setup_effects
  end

  def test_null_tmux_returns_tmux_instance
    tmux = @harness.null_tmux
    assert_instance_of Hiiro::Tmux, tmux
  end

  def test_null_git_returns_git_instance
    git = @harness.null_git
    assert_instance_of Hiiro::Git, git
  end

  def test_executor_records_tmux_calls
    tmux = @harness.null_tmux
    # server_running? calls @executor.check('tmux', 'has-session')
    tmux.server_running?
    executor = @harness.instance_variable_get(:@executor)
    assert executor.called?('tmux'), "expected executor to have recorded a tmux call"
    assert executor.called?('has-session'), "expected executor to have recorded a has-session call"
  end

  def test_executor_records_git_calls
    git = @harness.null_git
    # root calls @executor.capture('git', 'rev-parse', '--show-toplevel')
    git.root
    executor = @harness.instance_variable_get(:@executor)
    assert executor.called?('git'), "expected executor to have recorded a git call"
    assert executor.called?('rev-parse'), "expected executor to have recorded a rev-parse call"
  end

  def test_null_tmux_run_calls_use_null_executor
    tmux = @harness.null_tmux
    tmux.new_window(name: 'mywindow')
    executor = @harness.instance_variable_get(:@executor)
    assert executor.called?('new-window'), "expected executor to have recorded a new-window call"
  end

  def test_null_filesystem_starts_empty
    fs = @harness.instance_variable_get(:@fs)
    refute fs.exist?('/some/path')
  end

  def test_null_filesystem_write_and_read
    fs = @harness.instance_variable_get(:@fs)
    fs.write('/test/file.txt', 'hello')
    assert fs.exist?('/test/file.txt')
    assert_equal 'hello', fs.read('/test/file.txt')
  end

  def test_null_filesystem_tracks_writes
    fs = @harness.instance_variable_get(:@fs)
    fs.write('/a.txt', 'foo')
    fs.write('/b.txt', 'bar')
    assert_includes fs.writes, '/a.txt'
    assert_includes fs.writes, '/b.txt'
  end

  def test_null_filesystem_rm_removes_file
    fs = @harness.instance_variable_get(:@fs)
    fs.write('/tmp/gone.txt', 'bye')
    assert fs.exist?('/tmp/gone.txt')
    fs.rm('/tmp/gone.txt')
    refute fs.exist?('/tmp/gone.txt')
    assert_includes fs.deletes, '/tmp/gone.txt'
  end

  def test_executor_reset_clears_calls
    executor = @harness.instance_variable_get(:@executor)
    tmux = @harness.null_tmux
    tmux.server_running?
    assert executor.called?('tmux')
    executor.reset!
    refute executor.called?('tmux'), "expected calls to be cleared after reset!"
  end

  def test_multiple_null_tmux_instances_share_executor
    tmux1 = @harness.null_tmux
    tmux2 = @harness.null_tmux
    tmux1.server_running?
    tmux2.new_window(name: 'x')
    executor = @harness.instance_variable_get(:@executor)
    assert_equal 2, executor.calls.size
  end
end
