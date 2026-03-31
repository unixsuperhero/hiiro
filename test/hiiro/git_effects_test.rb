require 'test_helper'

class GitEffectsTest < Minitest::Test
  def setup
    @executor = Hiiro::Effects::NullExecutor.new
    @git = Hiiro::Git.new(nil, '/fake/repo', executor: @executor)
  end

  def test_checkout_calls_git_checkout
    @git.checkout('my-branch')
    assert @executor.called?('checkout')
    assert @executor.called?('my-branch')
  end

  def test_branch_exists_uses_check
    # NullExecutor returns true by default for check — no stub needed
    result = @git.branch_exists?('main')
    assert result
    assert @executor.called?('show-ref')
  end

  def test_delete_branch_uses_run
    @git.delete_branch('old-branch')
    assert @executor.called?('branch')
    assert @executor.called?('old-branch')
  end

  def test_default_executor_is_real
    git = Hiiro::Git.new
    assert_instance_of Hiiro::Effects::Executor, git.instance_variable_get(:@executor)
  end

  def test_root_uses_capture
    @executor.stub('rev-parse', '/fake/repo')
    root = @git.root
    assert_equal '/fake/repo', root
    assert @executor.called?('rev-parse')
  end

  def test_run_safe_returns_nil_for_empty_output
    # NullExecutor returns '' by default — run_safe should return nil
    result = @git.send(:run_safe, 'some-command')
    assert_nil result
  end
end
