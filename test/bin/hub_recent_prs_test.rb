require 'test_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../../bin/lib/hub'
require_relative '../../bin/lib/hub_recent_prs'

# HubRecentPRs shells out to `gh`; these tests put an executable fixture named
# gh first on PATH, so no network or credentials are involved.
class HubRecentPRsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('hub-prs')
    @old_path = ENV['PATH']
    ENV['PATH'] = "#{@dir}:#{@old_path}"
    @argv_log = File.join(@dir, 'argv.log')
  end

  def teardown
    ENV['PATH'] = @old_path
    FileUtils.rm_rf(@dir)
  end

  def fake_gh(stdout: '', stderr: '', code: 0)
    File.write(File.join(@dir, 'payload'), stdout)
    File.write(File.join(@dir, 'errload'), stderr)
    path = File.join(@dir, 'gh')
    File.write(path, <<~SH)
      #!/bin/sh
      printf '%s\\n' "$*" > '#{@argv_log}'
      cat '#{@dir}/payload'
      cat '#{@dir}/errload' >&2
      exit #{code}
    SH
    File.chmod(0o755, path)
  end

  def pr(number, repo, title, at, url: nil)
    { 'number' => number, 'title' => title, 'state' => 'open', 'updatedAt' => at,
      'url' => url || "https://github.com/#{repo}/pull/#{number}",
      'repository' => { 'name' => repo.split('/').last, 'nameWithOwner' => repo } }
  end

  def test_normalizes_and_sorts_newest_first_with_path_tiebreak
    fake_gh(stdout: JSON.generate([
      pr(1, 'a/old', "Old\n  one", '2026-01-01T00:00:00Z'),
      pr(9, 'b/tie', 'Tie B', '2026-05-05T10:00:00Z'),
      pr(3, 'a/tie', 'Tie A', '2026-05-05T12:00:00+02:00'),
      pr(7, 'c/new', 'Newest', '2026-09-01T08:30:00Z')
    ]))

    records = HubRecentPRs.fetch(limit: 20)

    assert_equal ['c/new#7 Newest', 'a/tie#3 Tie A', 'b/tie#9 Tie B', 'a/old#1 Old one'],
                 records.map { |r| r['name'] }
    assert_equal '2026-05-05T10:00:00Z', records[1]['timestamp'] # offset converted to UTC
    assert_equal 'https://github.com/a/tie/pull/3', records[1]['path']
    assert_equal %w[basis name path timestamp], records.first.keys.sort
    assert(records.all? { |r| r['basis'] == 'updated' })
  end

  def test_limit_truncates_after_sorting
    fake_gh(stdout: JSON.generate([pr(1, 'a/x', 'one', '2026-01-01T00:00:00Z'),
                                   pr(2, 'a/x', 'two', '2026-02-01T00:00:00Z')]))
    assert_equal ['a/x#2 two'], HubRecentPRs.fetch(limit: 1).map { |r| r['name'] }
  end

  def test_empty_results_are_distinct_from_auth_failures
    fake_gh(stdout: '[]')
    assert_equal [], HubRecentPRs.fetch(limit: 20)

    fake_gh(stderr: "To get started with GitHub CLI, please run:  gh auth login\n", code: 4)
    e = assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 20) }
    assert_includes e.message, 'gh auth login'
    refute_includes e.message, "\n"
  end

  def test_missing_gh_is_a_dependency_failure
    ENV['PATH'] = File.join(@dir, 'empty')
    e = assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 20) }
    assert_match(/gh is not installed/, e.message)
  end

  def test_malformed_payloads_raise
    fake_gh(stdout: 'not json')
    assert_match(/malformed JSON/, assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 3) }.message)

    fake_gh(stdout: '{"a":1}')
    assert_match(/expected an array/, assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 3) }.message)

    bad = pr(1, 'a/x', 't', '2026-01-01T00:00:00Z')
    { 'url' => nil, 'title' => nil, 'number' => '1', 'updatedAt' => 'yesterday',
      'repository' => { 'name' => 'x' } }.each do |key, value|
      fake_gh(stdout: JSON.generate([bad.merge(key => value)]))
      assert_raises(Hub::Error, "#{key}=#{value.inspect}") { HubRecentPRs.fetch(limit: 3) }
    end
  end

  def test_rejects_bad_limit_and_repo_before_running_gh
    fake_gh(stdout: '[]')
    [0, -1, 'x', 1001].each { |n| assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: n) } }
    assert_match(/maximum of 1000/, assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 1001) }.message)
    ['no-slash', 'a/b/c', '--x/y', 'a/b c'].each do |r|
      assert_raises(Hub::Error) { HubRecentPRs.fetch(limit: 5, repo: r) }
    end
    refute File.exist?(@argv_log), 'gh must not run for invalid input'
    assert_equal 1000, HubRecentPRs.validate_limit('1000')
  end
end
