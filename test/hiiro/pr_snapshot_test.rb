require 'test_helper'
require 'json'
require 'rbconfig'
require_relative '../support/fake_gh'

class PrSnapshotFetcherTest < Minitest::Test
  HEAD = 'a' * 40
  NEW_HEAD = 'b' * 40

  def setup
    @dir = Dir.mktmpdir('hiiro-fake-gh-')
    @state = File.join(@dir, 'state.json')
    @log = File.join(@dir, 'gh.log')
    @gh = FakeGh.install(@dir, @state, @log)
    @fetcher = Hiiro::PrSnapshot::Fetcher.new(runner: ->(*argv) { Hiiro::Shell.run3(@gh, *argv.drop(1)) })
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def state(prs)
    File.write(@state, JSON.generate('prs' => prs))
  end

  def ref(text) = Hiiro::PullRequestReference.qualified(text)
  def calls = File.readlines(@log).map { |line| JSON.parse(line) }

  def test_same_number_in_two_repositories_paginates_checks_and_reviews_completely
    state('team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => HEAD, 'checks' => 250, 'reviews' => 130 },
          'team/two#42' => { 'title' => 'two', 'state' => 'OPEN', 'head' => NEW_HEAD, 'checks' => 0, 'reviews' => 0 })
    one, two = ref('team/one#42'), ref('team/two#42')
    result = @fetcher.fetch([one, two])

    a, b = result.fetch(one), result.fetch(two)
    assert_equal [HEAD, 'one', 250, true, 130, true, nil],
                 [a.head_sha, a.fields['title'], a.checks.nodes.length, a.checks.complete, a.reviews.nodes.length, a.reviews.complete, a.error]
    assert_equal (1..250).map { |i| "check-#{i}" }, a.checks.nodes.map { |node| node['name'] }
    assert_equal 'reviewer-1', a.reviews.nodes.first.dig('author', 'login')
    assert_equal [NEW_HEAD, 'two', true, true], [b.head_sha, b.fields['title'], b.checks.known_empty?, b.reviews.known_empty?]
    # one batch per repository, two more check pages and one review page for team/one
    assert_equal [['name=one', nil], ['name=one', 'before=checks:150'], ['name=one', 'before=checks:50'], ['name=one', 'before=reviews:30'], ['name=two', nil]],
                 calls.map { |argv| [argv.find { |a| a.start_with?('name=') }, argv.find { |a| a.start_with?('before=') }] }
    assert calls.all? { |argv| argv.first(2) == %w[api graphql] }
  end

  def test_failed_later_page_keeps_fetched_nodes_and_reports_incomplete
    state('team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => HEAD, 'checks' => 250, 'reviews' => 130,
                             'fail' => { 'checks' => { '3' => 'exit' }, 'reviews' => { '2' => 'malformed' } } })
    snapshot = @fetcher.fetch([ref('team/one#42')]).fetch(ref('team/one#42'))
    assert_equal [200, false, 100, false], [snapshot.checks.nodes.length, snapshot.checks.complete, snapshot.reviews.nodes.length, snapshot.reviews.complete]
    assert_equal 'checks: page 3 failed: gh exited 1: HTTP 502: Bad Gateway (https://api.github.com/graphql); reviews: page 2 failed: malformed gh output', snapshot.error
    refute snapshot.complete?
    summary = Hiiro::CheckSummary.from_rollup(snapshot.checks.nodes, truncated: !snapshot.checks.complete)
    assert_equal [200, 0], [summary.success, summary.failed]
    refute summary.green?
  end

  def test_head_change_between_pages_is_a_failure_not_a_combined_snapshot
    state('team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => HEAD, 'checks' => 150, 'reviews' => 130,
                             'head_at' => { 'reviews' => { '2' => NEW_HEAD } } })
    result = @fetcher.fetch([ref('team/one#42')]).fetch(ref('team/one#42'))
    assert_instance_of Hiiro::PrSnapshot::Failure, result
    assert_equal 'head changed during refresh (aaaaaaa → bbbbbbb at reviews page 2)', result.error
  end

  def test_repeated_cursor_and_graphql_page_errors_stop_without_claiming_completeness
    state('team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => HEAD, 'checks' => 250, 'reviews' => 130,
                             'repeat_cursor' => { 'checks' => true }, 'fail' => { 'reviews' => { '2' => 'errors' } } })
    snapshot = @fetcher.fetch([ref('team/one#42')]).fetch(ref('team/one#42'))
    assert_equal [200, false, 100, false], [snapshot.checks.nodes.length, snapshot.checks.complete, snapshot.reviews.nodes.length, snapshot.reviews.complete]
    assert_equal 'checks: repeated cursor checks:150; reviews: page 2 failed: Something went wrong while executing your query.', snapshot.error
  end

  def test_partial_graphql_errors_fail_only_the_affected_pull_requests
    state('team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => HEAD, 'checks' => 3, 'reviews' => 2,
                             'error' => { 'reviews' => 'Resource not accessible by integration' } })
    result = @fetcher.fetch([ref('team/one#42'), ref('team/one#43')])
    snapshot, missing = result.fetch(ref('team/one#42')), result.fetch(ref('team/one#43'))
    assert_equal [3, true, [], false], [snapshot.checks.nodes.length, snapshot.checks.complete, snapshot.reviews.nodes, snapshot.reviews.complete]
    assert_equal 'reviews: repository.pr0.reviews: Resource not accessible by integration', snapshot.error
    assert_equal 'repository.pr1: Could not resolve to a PullRequest with the number of 43.', missing.error
  end

  def test_malformed_output_or_missing_gh_fails_every_reference
    File.write(@state, 'not json')
    failure = @fetcher.fetch([ref('team/one#42')]).fetch(ref('team/one#42'))
    assert_match(/\Agh exited 1: .*JSON::ParserError/m, failure.error)
    missing = Hiiro::PrSnapshot::Fetcher.new(runner: ->(*argv) { Hiiro::Shell.run3(File.join(@dir, 'absent-gh'), *argv.drop(1)) })
    failure = missing.fetch([ref('team/two#1')]).fetch(ref('team/two#1'))
    assert_match(/\Agh could not start: No such file or directory/, failure.error)
  end
end
