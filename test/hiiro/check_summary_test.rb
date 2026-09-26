require "test_helper"

class CheckSummaryTest < Minitest::Test
  ROLLUP = [
    { '__typename' => 'CheckRun', 'name' => 'rspec', 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS', 'detailsUrl' => 'u1' },
    { '__typename' => 'CheckRun', 'name' => 'lint',  'status' => 'IN_PROGRESS', 'conclusion' => nil },
    { '__typename' => 'StatusContext', 'context' => 'ISC code freeze', 'state' => 'FAILURE', 'targetUrl' => 'u3' },
    { '__typename' => 'StatusContext', 'context' => 'ci/other', 'state' => 'SUCCESS' },
  ].freeze

  def test_from_rollup_counts_match_legacy_summarize_checks
    s = Hiiro::CheckSummary.from_rollup(ROLLUP)

    assert_equal({ 'total' => 4, 'success' => 2, 'pending' => 1, 'failed' => 1, 'frozen' => 1 }, s.to_h)
    assert_equal s.to_h, Hiiro::Git::Pr.summarize_checks(ROLLUP)
  end

  def test_truncated_flag_is_retained_only_when_set
    assert_equal true, Hiiro::CheckSummary.from_rollup(ROLLUP, truncated: true).to_h['truncated']
    refute Hiiro::CheckSummary.from_rollup(ROLLUP, truncated: nil).to_h.key?('truncated')
    refute Hiiro::CheckSummary.from_rollup(ROLLUP).complete? == false
  end

  def test_nil_for_missing_or_empty_rollup
    assert_nil Hiiro::CheckSummary.from_rollup(nil)
    assert_nil Hiiro::CheckSummary.from_rollup([])
    assert_nil Hiiro::CheckSummary.from_rollup('junk')
    assert_nil Hiiro::CheckSummary.from_counts(nil)
  end

  def test_predicates
    s = Hiiro::CheckSummary.from_rollup(ROLLUP)
    assert s.red?
    refute s.green?
    refute s.pending?
    assert s.any_pending?
    assert s.only_frozen?

    green = Hiiro::CheckSummary.from_counts({ 'total' => 3, 'success' => 3, 'pending' => 0, 'failed' => 0, 'frozen' => 0 })
    assert green.green?
    refute green.red?

    waiting = Hiiro::CheckSummary.from_counts({ 'total' => 2, 'success' => 1, 'pending' => 1, 'failed' => 0, 'frozen' => 0 })
    assert waiting.pending?
    refute waiting.green?
  end

  def test_counts_by_outcome_defaults_missing_to_zero
    counts = Hiiro::CheckSummary.from_rollup(ROLLUP).counts_by_outcome
    assert_equal({ 'SUCCESS' => 2, 'IN_PROGRESS' => 1, 'FAILURE' => 1 }, counts)
    assert_equal 0, counts['CANCELLED']
  end

  def test_context_name_url_kind
    ctxs = Hiiro::CheckSummary.from_rollup(ROLLUP).contexts
    assert_equal [:check_run, :check_run, :status_context, :status_context], ctxs.map(&:kind)
    assert_equal %w[rspec lint], ctxs.first(2).map(&:name)
    assert_equal 'ISC code freeze', ctxs[2].name
    assert_equal 'u1', ctxs[0].url
    assert_equal 'u3', ctxs[2].url
    assert_nil ctxs[1].url
    assert ctxs[2].freeze?
  end

  def test_from_counts_keeps_stored_contexts
    s = Hiiro::CheckSummary.from_counts({ 'total' => 4, 'success' => 2, 'pending' => 1, 'failed' => 1, 'frozen' => 1 }, contexts: ROLLUP)
    assert_equal 4, s.contexts.length
    assert_equal 4, s.total
  end

  def test_to_row_matches_check_run_columns
    row = Hiiro::CheckContext.from_node(ROLLUP[0]).to_row(pr_number: 7)
    assert_equal 7, row[:pr_number]
    assert_equal 'rspec', row[:name]
    assert_equal 'u1', row[:url]
    assert_equal 'SUCCESS', row[:conclusion]
    assert_equal 'COMPLETED', row[:status]
    assert row[:updated_at]
  end

  def test_pr_predicates_delegate
    pr = Hiiro::Git::Pr.new(number: 1, checks: { 'total' => 1, 'success' => 0, 'pending' => 0, 'failed' => 1, 'frozen' => 0 })
    assert pr.red?
    refute pr.green?
    assert_nil Hiiro::Git::Pr.new(number: 2).red?
  end
end
