require 'test_helper'

class TestHarnessEffectsTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.new
    @harness.setup_effects
  end

  def test_null_herdr_returns_herdr_instance
    assert_instance_of Hiiro::Herdr, @harness.null_herdr
  end

  def test_null_git_returns_git_instance
    assert_instance_of Hiiro::Git, @harness.null_git
  end

  def test_executor_records_herdr_calls
    @harness.null_herdr.server_running?
    assert @harness.executor.called?('herdr')
    assert @harness.executor.called?('status')
  end

  def test_executor_records_git_calls
    @harness.null_git.root
    assert @harness.executor.called?('git')
    assert @harness.executor.called?('rev-parse')
  end

  def test_null_herdr_run_calls_use_null_executor
    @harness.null_herdr.new_tab(name: 'mytab')
    assert @harness.executor.called?('tab')
    assert @harness.executor.called?('create')
  end

  def test_null_filesystem_starts_empty
    refute @harness.null_fs.exist?('/some/path')
  end

  def test_null_filesystem_write_and_read
    @harness.null_fs.write('/test/file.txt', 'hello')
    assert @harness.null_fs.exist?('/test/file.txt')
    assert_equal 'hello', @harness.null_fs.read('/test/file.txt')
  end

  def test_null_filesystem_tracks_writes
    @harness.null_fs.write('/a.txt', 'foo')
    @harness.null_fs.write('/b.txt', 'bar')
    assert_includes @harness.null_fs.writes, '/a.txt'
    assert_includes @harness.null_fs.writes, '/b.txt'
  end

  def test_null_filesystem_rm_removes_file
    @harness.null_fs.write('/tmp/gone.txt', 'bye')
    @harness.null_fs.rm('/tmp/gone.txt')
    refute @harness.null_fs.exist?('/tmp/gone.txt')
    assert_includes @harness.null_fs.deletes, '/tmp/gone.txt'
  end

  def test_executor_reset_clears_calls
    @harness.null_herdr.server_running?
    assert @harness.executor.called?('herdr')
    @harness.executor.reset!
    refute @harness.executor.called?('herdr')
  end

  def test_multiple_null_herdr_instances_share_executor
    @harness.null_herdr.server_running?
    @harness.null_herdr.new_tab(name: 'x')
    assert_equal 2, @harness.executor.calls.size
  end
end
