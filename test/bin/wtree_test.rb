require "test_helper"

class WtreeTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-wtree")
  end

  def test_registers_expected_subcommands
    expected = %i[ls list add lock move prune remove repair unlock select copy]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_calls_git_worktree_list
    @harness.run_subcmd(:ls)

    assert_equal 1, @harness.system_calls.size
    assert_equal ['git', 'worktree', 'list'], @harness.system_calls.first
  end

  def test_ls_passes_extra_args
    @harness.run_subcmd(:ls, '--porcelain')

    assert_equal [['git', 'worktree', 'list', '--porcelain']], @harness.system_calls
  end

  def test_add_calls_git_worktree_add
    @harness.run_subcmd(:add, '../new-tree', 'my-branch')

    assert_equal [['git', 'worktree', 'add', '../new-tree', 'my-branch']], @harness.system_calls
  end

  def test_remove_calls_git_worktree_remove
    @harness.run_subcmd(:remove, '../old-tree')

    assert_equal [['git', 'worktree', 'remove', '../old-tree']], @harness.system_calls
  end

  def test_lock_calls_git_worktree_lock
    @harness.run_subcmd(:lock, '../my-tree')

    assert_equal [['git', 'worktree', 'lock', '../my-tree']], @harness.system_calls
  end

  def test_unlock_calls_git_worktree_unlock
    @harness.run_subcmd(:unlock, '../my-tree')

    assert_equal [['git', 'worktree', 'unlock', '../my-tree']], @harness.system_calls
  end

  def test_move_calls_git_worktree_move
    @harness.run_subcmd(:move, '../old-path', '../new-path')

    assert_equal [['git', 'worktree', 'move', '../old-path', '../new-path']], @harness.system_calls
  end

  def test_prune_calls_git_worktree_prune
    @harness.run_subcmd(:prune)

    assert_equal [['git', 'worktree', 'prune']], @harness.system_calls
  end

  def test_repair_calls_git_worktree_repair
    @harness.run_subcmd(:repair, '../my-tree')

    assert_equal [['git', 'worktree', 'repair', '../my-tree']], @harness.system_calls
  end

  def test_list_is_alias_for_ls
    # list should call run_subcmd(:ls, ...)
    # Since it delegates, we need to check it exists
    assert @harness.has_subcmd?(:list)
  end
end
