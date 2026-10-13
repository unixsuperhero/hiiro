require 'test_helper'
require_relative '../support/cli_sandbox'

# h commit select reads `git log` from a real repository and chooses in the
# shared `commits` picker on a pseudo-terminal; it prints the SHA with a newline.
class CommitTest < Minitest::Test
  include CliSandbox
  include CommitFixture

  def setup
    setup_sandbox
    @repo = File.join(@root, 'repo')
    @shas = commit_repo(@repo)
    @short = @shas.map { |sha| sha[0, 7] }
    ruby_in_sandbox('Hiiro::DB.setup!')
  end

  def teardown = teardown_sandbox

  def test_commit_log_reads_records_with_refs_and_log_options
    commits = Dir.chdir(@repo) { Hiiro::CommitLog.read('-n', '50') }
    assert_equal [
      [@shas[2], @short[2], 'fix | pipes: and colons', 'HEAD -> main', @repo],
      [@shas[1], @short[1], 'two', 'tag: v1', @repo],
      [@shas[0], @short[0], 'one', '', @repo],
    ], commits.map { |c| [c.sha, c.short, c.subject, c.decorations, c.repo] }
    assert_equal "#{@short[2]} (HEAD -> main) fix | pipes: and colons", commits[0].line(decorate: true)
    assert_equal "#{@short[1]} two", commits[1].line
    assert_equal ['commit', @repo, @shas[1]], commits[1].picker_item.identity

    assert_equal %w[fix one], Hiiro::CommitLog.read('--', 'a.txt', dir: @repo).map { |c| c.subject.split.first }
    assert_equal [@shas[2]], Hiiro::CommitLog.read('-n', '1', dir: @repo).map(&:sha)
  end

  def test_select_prints_the_chosen_sha_with_a_newline
    out, status, frame = pick('h-commit', ['select'], "j\r", chdir: @repo)
    assert_equal ['commits  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded',
                  "   #{@short[2]} (HEAD -> main) fix | pipes: and colons", ">  #{@short[1]} (tag: v1) two", "   #{@short[0]} one"], frame[0..4]
    assert_equal ["#{@short[1]}\n", 0], [out, status]

    out, status, = pick('h-commit', %w[sk -- b.txt], "\r", chdir: @repo)
    assert_equal ["#{@short[1]}\n", 0], [out, status]
  end

  def test_an_exclusion_rule_hides_a_commit_in_later_picks
    ruby_in_sandbox("Hiiro::PickerExclusion.create(picker: 'commits', scope: 'picker', mode: 'exact', field: 'id', " \
                    "pattern: #{JSON.generate(['commit', @repo, @shas[2]]).inspect}, created_at: 'now')")
    out, status, frame = pick('h-commit', ['select'], "\r", chdir: @repo)
    assert_equal ['commits  choices  (1 excluded)', 'Enter choose  ^E edit  ^X excluded', ">  #{@short[1]} (tag: v1) two", "   #{@short[0]} one", ''], frame[0..4]
    assert_equal ["#{@short[1]}\n", 0], [out, status]
  end

  def test_cancel_prints_nothing
    assert_equal ['', 0], pick('h-commit', ['select'], 'q', chdir: @repo).first(2)
  end

  def test_off_a_terminal_and_without_commits
    assert_equal ['', "ERROR: Choosing from commits needs a terminal\n", 1], run_bin('h-commit', 'select', chdir: @repo)

    empty = File.join(@root, 'empty')
    git_in(@root, 'init', '-q', empty)
    out, err, status = run_bin('h-commit', 'select', chdir: empty)
    assert_equal ["No commits found\n", 0], [out, status]
    assert_match(/does not have any commits yet/, err)
  end

  def test_default_prints_usage
    assert_equal [<<~TEXT, '', 0], run_bin('h-commit')
      Usage: h commit <subcommand> [args]

      Subcommands:
        select, sk  Select a commit using the picker and print its SHA
                    Additional args are passed to git log
    TEXT
  end
end
