require "test_helper"

class GitPrTest < Minitest::Test
  def test_pr_initialization
    pr = Hiiro::Git::Pr.new(
      number: 123,
      title: "Fix bug",
      state: "OPEN",
      url: "https://github.com/user/repo/pull/123",
      head_branch: "fix-bug",
      base_branch: "main"
    )

    assert_equal 123, pr.number
    assert_equal "Fix bug", pr.title
    assert_equal "OPEN", pr.state
    assert_equal "https://github.com/user/repo/pull/123", pr.url
    assert_equal "fix-bug", pr.head_branch
    assert_equal "main", pr.base_branch
  end

  def test_pr_open
    pr = Hiiro::Git::Pr.new(number: 1, state: "OPEN")
    assert pr.open?
    refute pr.closed?
    refute pr.merged?
  end

  def test_pr_closed
    pr = Hiiro::Git::Pr.new(number: 1, state: "CLOSED")
    refute pr.open?
    assert pr.closed?
    refute pr.merged?
  end

  def test_pr_merged
    pr = Hiiro::Git::Pr.new(number: 1, state: "MERGED")
    refute pr.open?
    refute pr.closed?
    assert pr.merged?
  end

  def test_pr_state_case_insensitive
    pr_open = Hiiro::Git::Pr.new(number: 1, state: "open")
    pr_closed = Hiiro::Git::Pr.new(number: 2, state: "Closed")
    pr_merged = Hiiro::Git::Pr.new(number: 3, state: "MeRgEd")

    assert pr_open.open?
    assert pr_closed.closed?
    assert pr_merged.merged?
  end

  def test_pr_to_s
    pr = Hiiro::Git::Pr.new(number: 42, title: "Add feature")

    assert_equal "#42: Add feature", pr.to_s
  end

  def test_pr_to_h
    pr = Hiiro::Git::Pr.new(
      number: 123,
      title: "Fix bug",
      state: "OPEN",
      url: "https://github.com/user/repo/pull/123"
    )

    hash = pr.to_h
    assert_equal 123, hash[:number]
    assert_equal "Fix bug", hash[:title]
    assert_equal "OPEN", hash[:state]
    assert_equal "https://github.com/user/repo/pull/123", hash[:url]
  end

  def test_pr_to_h_excludes_nil_values
    pr = Hiiro::Git::Pr.new(number: 123)

    hash = pr.to_h
    assert_equal 123, hash[:number]
    refute hash.key?(:title)
    refute hash.key?(:state)
  end

  def test_pr_from_gh_json
    data = {
      'number' => 456,
      'title' => 'Update docs',
      'state' => 'OPEN',
      'url' => 'https://github.com/user/repo/pull/456',
      'headRefName' => 'update-docs',
      'baseRefName' => 'main',
    }

    pr = Hiiro::Git::Pr.from_gh_json(data)

    assert_equal 456, pr.number
    assert_equal 'Update docs', pr.title
    assert_equal 'OPEN', pr.state
    assert_equal 'update-docs', pr.head_branch
    assert_equal 'main', pr.base_branch
  end

  def test_pr_nil_state_handling
    pr = Hiiro::Git::Pr.new(number: 1, state: nil)

    refute pr.open?
    refute pr.closed?
    refute pr.merged?
  end
end
