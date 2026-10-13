require 'test_helper'
require_relative '../support/cli_sandbox'

# h sha select chooses from the shared `commits` picker and prints the SHA
# without a newline; show and copy choose the same way when no SHA is given.
class ShaTest < Minitest::Test
  include CliSandbox
  include CommitFixture

  def setup
    setup_sandbox
    recorder('pbcopy', %(cat > "#{@root}/clipboard"\n))
    @repo = File.join(@root, 'repo')
    @shas = commit_repo(@repo)
    @short = @shas.map { |sha| sha[0, 7] }
    ruby_in_sandbox('Hiiro::DB.setup!')
  end

  def teardown = teardown_sandbox

  def clipboard = File.read(File.join(@root, 'clipboard'))

  def test_select_prints_the_sha_without_a_newline
    out, status, frame = pick('h-sha', ['select'], "jj\r", chdir: @repo)
    assert_equal ['commits  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded',
                  "   #{@short[2]} fix | pipes: and colons", "   #{@short[1]} two", ">  #{@short[0]} one"], frame[0..4]
    assert_equal [@short[0], 0], [out, status]
  end

  def test_search_then_choose
    out, status, frame = pick('h-sha', ['select'], "/pipes\r\r", chdir: @repo)
    assert_equal [">  #{@short[2]} fix | pipes: and colons", ''], frame[2..3]
    assert_equal [@short[2], 0], [out, status]
  end

  def test_rules_saved_for_h_commit_apply_here
    ruby_in_sandbox("Hiiro::PickerExclusion.create(picker: 'commits', scope: 'picker', mode: 'regex', field: 'subject', " \
                    "pattern: '^(one|two)$', created_at: 'now')")
    out, status, frame = pick('h-sha', ['select'], "\r", chdir: @repo)
    assert_equal ['commits  choices  (2 excluded)', 'Enter choose  ^E edit  ^X excluded', ">  #{@short[2]} fix | pipes: and colons", ''], frame[0..3]
    assert_equal [@short[2], 0], [out, status]
  end

  def test_copy_and_show_without_a_sha_choose_in_process
    out, status, = pick('h-sha', ['copy'], "j\r", chdir: @repo)
    assert_equal ["Copied #{@short[1]} to clipboard\n", 0], [out, status]
    assert_equal @short[1], clipboard

    out, status, = pick('h-sha', ['show'], "jj\r", chdir: @repo, env: { 'GIT_PAGER' => 'cat' })
    assert_equal 0, status
    assert_equal "commit #{@shas[0]}\n", out.lines.first
    assert_match(/^\+one$/, out)
  end

  def test_explicit_sha_ls_and_empty_repositories
    assert_equal ["Copied abc123 to clipboard\n", '', 0], run_bin('h-sha', 'copy', 'abc123', chdir: @repo)
    assert_equal 'abc123', clipboard
    assert_equal [git_in(@repo, 'log', '--oneline', '-2'), '', 0], run_bin('h-sha', 'ls', '-2', chdir: @repo)
    assert_equal "commit #{@shas[1]}\n", run_bin('h-sha', 'show', @short[1], chdir: @repo).first.lines.first

    assert_equal ['', "ERROR: Choosing from commits needs a terminal\n", 1], run_bin('h-sha', 'select', chdir: @repo)

    empty = File.join(@root, 'empty')
    git_in(@root, 'init', '-q', empty)
    out, err, status = run_bin('h-sha', 'select', chdir: empty)
    assert_equal ['', 0], [out, status]
    assert_equal 'No commits found', err.lines.last.chomp
    assert_equal ['', 0], run_bin('h-sha', 'copy', chdir: empty).values_at(0, 2)
  end
end
