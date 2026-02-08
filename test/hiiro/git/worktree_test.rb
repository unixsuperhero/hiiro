require "test_helper"

class GitWorktreeTest < Minitest::Test
  def test_worktree_initialization
    worktree = Hiiro::Git::Worktree.new(
      path: "/home/user/project",
      head: "abc123",
      branch: "main"
    )

    assert_equal "/home/user/project", worktree.path
    assert_equal "abc123", worktree.head
    assert_equal "main", worktree.branch
    refute worktree.detached?
    refute worktree.bare?
  end

  def test_worktree_detached
    worktree = Hiiro::Git::Worktree.new(
      path: "/home/user/project",
      head: "abc123",
      detached: true
    )

    assert worktree.detached?
    assert_nil worktree.branch
  end

  def test_worktree_bare
    worktree = Hiiro::Git::Worktree.new(
      path: "/home/user/.bare",
      bare: true
    )

    assert worktree.bare?
  end

  def test_worktree_name
    worktree = Hiiro::Git::Worktree.new(path: "/home/user/work/my-feature")

    assert_equal "my-feature", worktree.name
  end

  def test_worktree_match_exact_path
    worktree = Hiiro::Git::Worktree.new(path: "/home/user/project")

    assert worktree.match?("/home/user/project")
  end

  def test_worktree_match_subpath
    worktree = Hiiro::Git::Worktree.new(path: "/home/user/project")

    assert worktree.match?("/home/user/project/src/main.rb")
  end

  def test_worktree_match_different_path
    worktree = Hiiro::Git::Worktree.new(path: "/home/user/project")

    refute worktree.match?("/home/user/other")
    refute worktree.match?("/home/user/project-extra")
  end

  def test_worktree_to_h
    worktree = Hiiro::Git::Worktree.new(
      path: "/home/user/project",
      head: "abc123",
      branch: "main"
    )

    hash = worktree.to_h
    assert_equal "/home/user/project", hash[:path]
    assert_equal "abc123", hash[:head]
    assert_equal "main", hash[:branch]
  end

  def test_worktree_from_porcelain_block
    lines = [
      "worktree /home/user/project",
      "HEAD abc123def456",
      "branch refs/heads/main",
    ]

    worktree = Hiiro::Git::Worktree.from_porcelain_block(lines)

    assert_equal "/home/user/project", worktree.path
    assert_equal "abc123def456", worktree.head
    assert_equal "main", worktree.branch
    refute worktree.detached?
  end

  def test_worktree_from_porcelain_block_detached
    lines = [
      "worktree /home/user/detached-wt",
      "HEAD abc123def456",
      "detached",
    ]

    worktree = Hiiro::Git::Worktree.from_porcelain_block(lines)

    assert_equal "/home/user/detached-wt", worktree.path
    assert worktree.detached?
    assert_nil worktree.branch
  end

  def test_worktree_from_porcelain_block_bare
    lines = [
      "worktree /home/user/.bare",
      "bare",
    ]

    worktree = Hiiro::Git::Worktree.from_porcelain_block(lines)

    assert_equal "/home/user/.bare", worktree.path
    assert worktree.bare?
  end
end

class GitWorktreesTest < Minitest::Test
  def test_worktrees_from_porcelain
    output = <<~PORCELAIN
      worktree /home/user/.bare
      bare

      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/feature
      HEAD def456
      branch refs/heads/feature
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    assert_equal 3, worktrees.count
  end

  def test_worktrees_enumerable
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/feature
      HEAD def456
      branch refs/heads/feature
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    paths = worktrees.map(&:path)
    assert_includes paths, "/home/user/main"
    assert_includes paths, "/home/user/feature"
  end

  def test_worktrees_find_by_path
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    result = worktrees.find_by_path("/home/user/main")
    assert_equal "main", result.branch
  end

  def test_worktrees_find_by_name
    output = <<~PORCELAIN
      worktree /home/user/my-feature
      HEAD abc123
      branch refs/heads/feature
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    result = worktrees.find_by_name("my-feature")
    assert_equal "/home/user/my-feature", result.path
  end

  def test_worktrees_find_by_branch
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/feature
      HEAD def456
      branch refs/heads/feature
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    result = worktrees.find_by_branch("feature")
    assert_equal "/home/user/feature", result.path
  end

  def test_worktrees_matching
    output = <<~PORCELAIN
      worktree /home/user/project
      HEAD abc123
      branch refs/heads/main
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    result = worktrees.matching("/home/user/project/src")
    assert_equal "/home/user/project", result.path
  end

  def test_worktrees_without_bare
    output = <<~PORCELAIN
      worktree /home/user/.bare
      bare

      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)
    non_bare = worktrees.without_bare

    assert_equal 1, non_bare.count
    assert_equal "/home/user/main", non_bare.first.path
  end

  def test_worktrees_detached
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/detached
      HEAD def456
      detached
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)
    detached = worktrees.detached

    assert_equal 1, detached.count
    assert detached.first.detached?
  end

  def test_worktrees_with_branch
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/detached
      HEAD def456
      detached
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)
    with_branch = worktrees.with_branch

    assert_equal 1, with_branch.count
    refute with_branch.first.detached?
  end

  def test_worktrees_names
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main

      worktree /home/user/feature
      HEAD def456
      branch refs/heads/feature
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    assert_equal %w[main feature], worktrees.names
  end

  def test_worktrees_paths
    output = <<~PORCELAIN
      worktree /home/user/main
      HEAD abc123
      branch refs/heads/main
    PORCELAIN

    worktrees = Hiiro::Git::Worktrees.from_porcelain(output)

    assert_equal ["/home/user/main"], worktrees.paths
  end

  def test_worktrees_empty
    worktrees = Hiiro::Git::Worktrees.from_porcelain("")

    assert worktrees.empty?
    assert_equal 0, worktrees.size
  end

  def test_worktrees_from_porcelain_nil
    worktrees = Hiiro::Git::Worktrees.from_porcelain(nil)

    assert worktrees.empty?
  end
end
