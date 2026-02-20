require "test_helper"

class BranchTest < Minitest::Test
  def setup
    @mock_git = MockGit.new
    mock = @mock_git  # capture for closure

    @harness = Hiiro::TestHarness.load_bin("bin/h-branch") do
      define_singleton_method(:git) { mock }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[edit save current info select copy co checkout rm remove duplicate test push diff changed ahead behind log forkpoint ancestor]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_current_prints_current_branch
    # This uses backticks internally via git helper
    # Just verify it doesn't crash
    @harness.run_subcmd(:current)
  end

  def test_checkout_with_branch_calls_git_checkout
    @harness.run_subcmd(:co, 'feature-branch')

    assert_equal [['git', 'checkout', 'feature-branch']], @harness.system_calls
  end

  def test_checkout_with_extra_args
    @harness.run_subcmd(:checkout, 'feature-branch', '-b')

    assert_equal [['git', 'checkout', 'feature-branch', '-b']], @harness.system_calls
  end

  def test_remove_with_branch_calls_git_branch_delete
    @harness.run_subcmd(:rm, 'old-branch')

    assert_equal [['git', 'branch', '-d', 'old-branch']], @harness.system_calls
  end

  def test_remove_with_force_flag
    @harness.run_subcmd(:remove, 'old-branch', '-D')

    assert_equal [['git', 'branch', '-d', 'old-branch', '-D']], @harness.system_calls
  end

  def test_duplicate_creates_new_branch_from_source
    @mock_git.current_branch = 'main'
    @harness.run_subcmd(:duplicate, 'new-branch', 'source-branch')

    assert_equal [['git', 'branch', 'new-branch', 'source-branch']], @harness.system_calls
  end

  def test_duplicate_uses_current_branch_as_default_source
    @mock_git.current_branch = 'main'
    @harness.run_subcmd(:duplicate, 'new-branch')

    assert_equal [['git', 'branch', 'new-branch', 'main']], @harness.system_calls
  end

  def test_push_basic
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push)

    call = @harness.system_calls.first
    assert_equal 'git', call[0]
    assert_equal 'push', call[1]
    assert_includes call, 'origin'
    assert_includes call, 'feature:feature'
  end

  def test_push_with_force_flag
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-F')

    call = @harness.system_calls.first
    assert_includes call, '--force'
  end

  def test_push_with_set_upstream_flag
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-u')

    call = @harness.system_calls.first
    assert_includes call, '-u'
  end

  def test_push_with_custom_remote
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-r', 'upstream')

    call = @harness.system_calls.first
    assert_includes call, 'upstream'
    refute_includes call, 'origin'
  end

  # Mock classes
  class MockGit
    attr_accessor :current_branch, :branches_list

    def initialize
      @current_branch = 'main'
      @branches_list = ['main', 'develop', 'feature-x']
    end

    def branch
      @current_branch
    end

    def branches(sort_by: nil, ignore_case: false)
      @branches_list
    end
  end
end
