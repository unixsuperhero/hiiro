require "test_helper"

class GitBranchComparisonTest < Minitest::Test
  def setup
    @ex = Hiiro::Effects::NullExecutor.new
    @git = Hiiro::Git.new(nil, '/tmp', executor: @ex)
  end

  def test_policy_picks_first_existing_ref
    @ex.stub('rev-parse --verify --quiet main', false)
    @ex.stub('rev-parse --verify --quiet master', true)
    cmp = @git.compare(base_policy: :local_main)

    assert_equal 'master', cmp.target
    assert_equal :policy, cmp.target_source
    assert_equal 'master..HEAD', cmp.two_dot_range
  end

  def test_remote_first_policy_order
    @ex.stub('rev-parse --verify --quiet origin/master', false)
    @ex.stub('rev-parse --verify --quiet master', false)
    @ex.stub('rev-parse --verify --quiet origin/main', true)
    assert_equal 'origin/main', @git.compare(base_policy: :remote_first).target
  end

  def test_fallback_and_none
    @ex.stub('rev-parse --verify --quiet', false)
    assert_equal 'HEAD~1', @git.compare(fallback: 'HEAD~1').target
    assert_equal :fallback, @git.compare(fallback: 'HEAD~1').target_source

    none = @git.compare
    refute none.resolved?
    assert_nil none.two_dot_range
    assert_nil none.fork_point
    assert_equal [], none.changed_paths
  end

  def test_explicit_target_skips_policy
    cmp = @git.compare(source: 'feature', target: 'develop')
    assert_equal :explicit, cmp.target_source
    assert_equal 'develop..feature', cmp.two_dot_range
    refute @ex.called?('rev-parse --verify')
  end

  def test_ahead_behind_and_ancestor
    @ex.stub('rev-list --count main..HEAD', "4\n")
    @ex.stub('rev-list --count HEAD..main', "12\n")
    @ex.stub('merge-base --is-ancestor main HEAD', true)
    cmp = @git.compare(target: 'main')

    assert_equal 4, cmp.ahead
    assert_equal 12, cmp.behind
    assert cmp.ancestor?
  end

  def test_fork_point_falls_back_to_merge_base
    @ex.stub('merge-base --fork-point main HEAD', "")
    @ex.stub('merge-base main HEAD', "abc123\n")
    cmp = @git.compare(target: 'main')

    assert_equal 'abc123', cmp.fork_point
    assert_equal 'abc123...HEAD', cmp.three_dot_range
    assert_equal 'abc123..HEAD', cmp.fork_range
  end

  def test_changed_paths_relative_flag
    @ex.stub('merge-base --fork-point main HEAD', "abc123\n")
    @ex.stub('diff --name-only --relative abc123...HEAD', "a.rb\nb/c.rb\n")
    @ex.stub('diff --name-only abc123...HEAD', "lib/a.rb\n")
    cmp = @git.compare(target: 'main')

    assert_equal %w[a.rb b/c.rb], cmp.changed_paths
    assert_equal %w[lib/a.rb], cmp.changed_paths(relative: false)
  end
end
