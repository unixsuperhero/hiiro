require "test_helper"

class GitBranchTest < Minitest::Test
  def test_branch_initialization
    branch = Hiiro::Git::Branch.new(name: "main")

    assert_equal "main", branch.name
    assert_equal "refs/heads/main", branch.ref
    refute branch.current?
  end

  def test_branch_with_current_flag
    branch = Hiiro::Git::Branch.new(name: "main", current: true)

    assert branch.current?
  end

  def test_branch_local
    branch = Hiiro::Git::Branch.new(name: "feature", ref: "refs/heads/feature")

    assert branch.local?
    refute branch.remote?
  end

  def test_branch_remote
    branch = Hiiro::Git::Branch.new(name: "origin/main", ref: "refs/remotes/origin/main")

    assert branch.remote?
    refute branch.local?
  end

  def test_branch_to_s
    branch = Hiiro::Git::Branch.new(name: "feature-branch")

    assert_equal "feature-branch", branch.to_s
  end

  def test_branch_to_h
    branch = Hiiro::Git::Branch.new(name: "main", head: "abc123", current: true)

    hash = branch.to_h
    assert_equal "main", hash[:name]
    assert_equal "refs/heads/main", hash[:ref]
    assert_equal "abc123", hash[:head]
    assert hash[:current]
  end

  def test_branch_to_h_excludes_nil_values
    branch = Hiiro::Git::Branch.new(name: "main")

    hash = branch.to_h
    refute hash.key?(:head)
    refute hash.key?(:upstream)
  end

  def test_from_format_line
    branch = Hiiro::Git::Branch.from_format_line("  feature-branch  ")

    assert_equal "feature-branch", branch.name
  end
end

class GitBranchesTest < Minitest::Test
  def test_branches_from_names
    branches = Hiiro::Git::Branches.from_names(%w[main develop feature])

    assert_equal 3, branches.count
    assert_equal %w[main develop feature], branches.names
  end

  def test_branches_enumerable
    branches = Hiiro::Git::Branches.from_names(%w[main develop])

    names = branches.map(&:name)
    assert_equal %w[main develop], names
  end

  def test_branches_find_by_name
    branches = Hiiro::Git::Branches.from_names(%w[main develop feature])

    result = branches.find_by_name("develop")
    assert_equal "develop", result.name
  end

  def test_branches_find_by_name_not_found
    branches = Hiiro::Git::Branches.from_names(%w[main develop])

    result = branches.find_by_name("nonexistent")
    assert_nil result
  end

  def test_branches_matching
    branches = Hiiro::Git::Branches.from_names(%w[feature-a feature-b main])

    result = branches.matching("feature")
    assert_equal 2, result.count
    assert_equal %w[feature-a feature-b], result.names
  end

  def test_branches_containing
    branches = Hiiro::Git::Branches.from_names(%w[add-feature remove-feature main])

    result = branches.containing("feature")
    assert_equal 2, result.count
  end

  def test_branches_empty
    branches = Hiiro::Git::Branches.from_names([])

    assert branches.empty?
    assert_equal 0, branches.size
  end

  def test_branches_to_a
    branches = Hiiro::Git::Branches.from_names(%w[main develop])

    array = branches.to_a
    assert_kind_of Array, array
    assert_equal 2, array.length
  end
end
