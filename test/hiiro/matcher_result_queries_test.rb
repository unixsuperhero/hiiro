require "test_helper"

class MatcherResultQueriesTest < Minitest::Test
  ITEMS = %w[apple apricot banana].freeze

  def test_result_and_path_result_share_answers
    result = Hiiro::Matcher.by_prefix(ITEMS, 'ap')
    assert result.ambiguous?
    assert_equal 2, result.count
    assert_nil result.match
    assert_equal 'apple', result.first.item
    assert_nil result.resolved
    assert_equal 'ap', result.query

    exact = Hiiro::Matcher.by_prefix(ITEMS, 'apple')
    assert exact.exact?
    assert_equal 'apple', exact.resolved.item

    path = Hiiro::Matcher.new(%w[task/sub task/other], nil).resolve_path('t/s')
    assert path.one?
    assert_equal 'task/sub', path.resolved.item
    assert_equal 't/s', path.query
    assert_kind_of Hiiro::Matcher::ResultQueries, path
  end
end
