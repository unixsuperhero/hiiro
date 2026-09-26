require "test_helper"

class PullRequestReferenceTest < Minitest::Test
  URL = 'https://github.com/instacart/carrot/pull/4521'

  def test_from_url
    ref = Hiiro::PullRequestReference.from_url(URL)
    assert_equal 4521, ref.number
    assert_equal '4521', ref.number_string
    assert_equal 'instacart/carrot', ref.repo.path
    assert_equal [4521, 'instacart/carrot'], ref.key
    assert_equal ['-R', 'instacart/carrot'], ref.repo_args
    assert_equal URL, ref.url
    assert_equal 'instacart/carrot#4521', ref.to_s
  end

  def test_parse_number_forms
    %w[4521 #4521].each do |input|
      ref = Hiiro::PullRequestReference.parse(input)
      assert_equal 4521, ref.number
      assert_nil ref.repo
      assert_equal [4521, nil], ref.key
      assert_equal [], ref.repo_args
      assert_nil ref.url
    end
    assert_equal 4521, Hiiro::PullRequestReference.parse(4521).number
    assert_equal URL, Hiiro::PullRequestReference.parse(URL).url
  end

  def test_parse_rejects_non_references
    assert_nil Hiiro::PullRequestReference.parse('feature-branch')
    assert_nil Hiiro::PullRequestReference.parse(nil)
    assert_nil Hiiro::PullRequestReference.parse('')
    assert_nil Hiiro::PullRequestReference.from_url('https://example.com/pull/1')
  end

  def test_default_repo
    ref = Hiiro::PullRequestReference.parse('12', default_repo: 'instacart/carrot')
    assert_equal 'instacart/carrot', ref.repo.path
  end

  def test_matches_number_and_repo
    ref = Hiiro::PullRequestReference.from_url(URL)
    same_repo  = Hiiro::Git::Pr.new(number: '4521', repo: 'instacart/carrot')
    other_repo = Hiiro::Git::Pr.new(number: 4521, repo: 'other/repo')
    legacy     = Hiiro::Git::Pr.new(number: 4521)
    by_url     = Hiiro::Git::Pr.new(number: 4521, url: URL)

    assert ref.matches?(same_repo)
    refute ref.matches?(other_repo)
    assert ref.matches?(legacy)
    assert ref.matches?(by_url)
    refute ref.matches?(Hiiro::Git::Pr.new(number: 1))

    bare = Hiiro::PullRequestReference.parse('4521')
    assert bare.matches?(other_repo)
  end

  def test_git_pr_factories_delegate
    pr = Hiiro::Git::Pr.from_link(URL)
    assert_equal '4521', pr.number
    assert_equal 'instacart/carrot', pr.repo
    assert_equal URL, pr.url
    assert Hiiro::Git::Pr.is_link?(URL)
    refute Hiiro::Git::Pr.is_link?('4521')
    assert_equal '77', Hiiro::Git::Pr.from_number(' 77 ').number
    assert_nil Hiiro::Git::Pr.from_number('abc')
    assert_equal 'instacart/carrot', Hiiro::Git::Pr.repo_from_url(URL)
    assert_nil Hiiro::Git::Pr.repo_from_url(nil)
  end

  def test_repository_identity_parse_and_equality
    a = Hiiro::RepositoryIdentity.parse('instacart/carrot')
    b = Hiiro::RepositoryIdentity.parse('https://github.com/instacart/carrot.git')
    assert_equal a, b
    assert_equal a.hash, b.hash
    assert_equal 'https://github.com/instacart/carrot', a.url
    assert_nil Hiiro::RepositoryIdentity.parse('nope')
  end
end
