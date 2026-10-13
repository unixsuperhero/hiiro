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

  def test_bare_numbers_are_qualified_only_by_explicit_repository_context
    ref = Hiiro::PullRequestReference.parse('12', repo: 'instacart/carrot')
    assert_equal ['instacart/carrot#12', true], [ref.to_s, ref.qualified?]
    assert_equal 'other/repo#7', Hiiro::PullRequestReference.parse('other/repo#7', repo: 'instacart/carrot').to_s
    assert_equal URL, Hiiro::PullRequestReference.parse(URL, repo: 'other/repo').url
    assert_equal 'other/repo#7', Hiiro::PullRequestReference.qualified('other/repo#7').to_s
    assert_nil Hiiro::PullRequestReference.qualified('7')
    refute Hiiro::PullRequestReference.parse('#7').qualified?
  end

  def test_equality_requires_the_same_repository
    a = Hiiro::PullRequestReference.parse('team/one#42')
    assert_equal a, Hiiro::PullRequestReference.from_url('https://github.com/team/one/pull/42')
    refute_equal a, Hiiro::PullRequestReference.parse('team/two#42')
    refute_equal a, Hiiro::PullRequestReference.parse('42')
    assert_equal 2, [a, Hiiro::PullRequestReference.parse('team/two#42'), Hiiro::PullRequestReference.parse('team/one#42')].uniq.length
    assert_equal a, Hiiro::Git::Pr.new(number: '42', url: 'https://github.com/team/one/pull/42').reference
  end

  def test_git_pr_factories_delegate
    pr = Hiiro::Git::Pr.from_link(URL)
    assert_equal '4521', pr.number
    assert_equal 'instacart/carrot', pr.repo
    assert_equal URL, pr.url
    assert Hiiro::Git::Pr.is_link?(URL)
    refute Hiiro::Git::Pr.is_link?('4521')
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
