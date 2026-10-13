require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require_relative '../support/fake_gh'

# Actual h-pr, h-cpr, and h-pr-monitor subprocesses. PATH is a fixture
# directory (fake gh, logging terminal-notifier, scripted editor) plus system
# directories; nothing reaches GitHub, a notifier, a browser, or an agent.
class PrActionsCliTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  A = 'a' * 40
  B = 'b' * 40
  FAILED = { '__typename' => 'CheckRun', 'name' => 'lint', 'status' => 'COMPLETED', 'conclusion' => 'FAILURE',
             'detailsUrl' => 'https://ci.example.test/lint' }.freeze
  PENDING = { '__typename' => 'CheckRun', 'name' => 'build', 'status' => 'IN_PROGRESS', 'conclusion' => nil }.freeze

  def setup
    @dir = Dir.mktmpdir('hiiro-pr-actions-')
    @bin = File.join(@dir, 'bin')
    @home = File.join(@dir, 'home')
    FileUtils.mkdir_p([@bin, @home])
    @state = File.join(@dir, 'state.json')
    @log = File.join(@dir, 'gh.log')
    @notes = File.join(@dir, 'notify.log')
    @db = File.join(@dir, 'hiiro.db')
    FakeGh.install(@bin, @state, @log)
    File.write(File.join(@bin, 'terminal-notifier'), "#!/bin/sh\nprintf '%s\\n' \"$*\" >> #{@notes}\n")
    File.write(File.join(@bin, 'fake-editor'), <<~SH)
      #!/bin/sh
      [ -n "$EDIT_EXIT" ] && exit $EDIT_EXIT
      exec #{RbConfig.ruby} -e "$EDIT_SCRIPT" "$1"
    SH
    File.chmod(0o755, File.join(@bin, 'terminal-notifier'), File.join(@bin, 'fake-editor'))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def env(extra = {})
    { 'HOME' => @home, 'PATH' => "#{@bin}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8', 'HIIRO_TEST_DB' => "sqlite://#{@db}",
      'EDITOR' => File.join(@bin, 'fake-editor'), 'VISUAL' => File.join(@bin, 'fake-editor') }
      .merge(ENV.slice('BUNDLE_PATH')).merge(extra)
  end

  def run_bin(bin, *args, edit: nil, edit_exit: nil, chdir: @dir)
    extra = { 'EDIT_SCRIPT' => edit.to_s }
    extra['EDIT_EXIT'] = edit_exit.to_s if edit_exit
    out, status = Open3.capture2e(env(extra), RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', bin), *args,
                                  unsetenv_others: true, chdir: chdir)
    [out.gsub(/\e\[[0-9;]*m/, ''), status.exitstatus]
  end

  def pr(*args, **opts) = run_bin('h-pr', *args, **opts)

  # Lines h-pr prints about outcomes (fake gh's own chatter filtered out).
  def outcome_lines(out) = out.lines.map(&:chomp).reject { |line| line.start_with?('fake gh', 'Pull request') }

  def write_state(prs, **rest)
    File.write(@state, JSON.generate({ 'repo' => 'team/one', 'prs' => prs }.merge(rest.transform_keys(&:to_s))))
  end

  def base_prs(two_checks: [FAILED])
    { 'team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => A, 'checks' => 2, 'reviews' => 1 },
      'team/two#5' => { 'title' => 'two', 'state' => 'OPEN', 'head' => B, 'checks' => two_checks, 'reviews' => 0 } }
  end

  def gh_calls(verb) = File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) }.select { |argv| argv.first(2) == ['pr', verb] } : []
  def notes = File.exist?(@notes) ? File.readlines(@notes, chomp: true) : []
  def queue_dir = File.join(@home, '.local/share/hiiro/queue/pending')
  def queued = Dir.exist?(queue_dir) ? Dir.children(queue_dir).sort : []

  def edit_to(yaml) = "File.write(ARGV[0], #{yaml.inspect})"

  def track_both
    pr('track', 'team/one#42')
    pr('track', 'team/two#5')
  end

  def test_single_and_bulk_merge_share_validation_targets_and_failure_status
    write_state(base_prs, actions: { 'team/two#5:merge' => { 'exit' => 1, 'stderr' => 'Pull request team/two#5 is not mergeable' } })
    track_both

    out, code = pr('merge', 'team/two#5', '--squash')
    assert_equal [['✗ team/two#5 merge: gh failed (exit 1)'], 1], [outcome_lines(out), code]
    out, code = pr('mmerge', edit: edit_to("prs:\n- team/one#42\n- https://github.com/team/two/pull/5\nstrategy: squash\ndelete_branch: false\n"))
    assert_equal [['✓ team/one#42 merge', '✗ team/two#5 merge: gh failed (exit 1)', 'merge: 1 succeeded, 1 failed'], 1], [outcome_lines(out), code]
    assert_equal [%w[pr merge https://github.com/team/two/pull/5 --squash], %w[pr merge https://github.com/team/one/pull/42 --squash],
                  %w[pr merge https://github.com/team/two/pull/5 --squash]], gh_calls('merge')

    assert_equal ["ERROR: merge: choose one of --merge, --squash, --rebase\n", 1], pr('merge', 'team/one#42', '--squash', '--rebase')
    assert_equal ["Invalid selection: merge: strategy must be one of merge, squash, rebase or blank\n", 1],
                 pr('mmerge', edit: edit_to("prs:\n- team/one#42\nstrategy: fast\n"))
    assert_equal ["ERROR: Not a PR reference: nonsense\n", 1], pr('merge', 'nonsense')
    assert_equal ["Invalid selection: Not a PR reference: nonsense\n", 1], pr('mmerge', edit: edit_to("prs:\n- team/one#42\n- nonsense\n"))
    assert_equal ["ERROR: comment: empty comment\n", 1], pr('comment', 'team/one#42', '-b', ' ')
    assert_equal ["Invalid selection: comment: empty comment\n", 1], pr('mcomment', edit: edit_to("prs:\n- team/one#42\ncomment: ' '\n"))
    assert_equal 3, gh_calls('merge').length
    assert_empty gh_calls('comment')
  end

  def test_bulk_selection_distinguishes_cancel_invalid_and_empty_and_mutates_nothing
    write_state(base_prs)
    track_both

    assert_equal ["Cancelled: editor exited unsuccessfully\n", 0], pr('mready', edit_exit: 1)
    assert_equal ["Cancelled: document unchanged\n", 0], pr('mready', edit: '')
    assert_equal ["Cancelled: empty document\n", 0], pr('mready', edit: edit_to(''))
    out, code = pr('mready', edit: edit_to('prs: ['))
    assert_equal 1, code
    assert_match(/\AInvalid selection: invalid YAML: .*did not find expected node content/, out)
    assert_equal ["Invalid selection: prs must be a list\n", 1], pr('mready', edit: edit_to("prs: team/one#42\n"))
    assert_equal ["No PRs selected; nothing to do.\n", 0], pr('mready', edit: edit_to("prs: []\n"))
    assert_empty gh_calls('ready')

    out, code = pr('mto-draft', edit: edit_to("prs:\n- team/two#5\n"))
    assert_equal [['✓ team/two#5 to-draft'], 0], [outcome_lines(out), code]
    assert_equal [%w[pr ready --undo https://github.com/team/two/pull/5]], gh_calls('ready')
  end

  def test_untrack_and_fix_run_through_the_same_action_single_or_bulk
    write_state(base_prs)
    track_both
    pr('tag', 'team/one#42', 'keep')

    assert_equal ["✓ team/two#5 fix: queued pr-fix-team-two-5-bbbbbbb\nRun 'h queue run' to start.\n", 0], pr('fix', 'team/two#5')
    out, code = pr('mfix', edit: edit_to("prs:\n- team/two#5\nrun: false\n"))
    assert_equal ["✓ team/two#5 fix: queued pr-fix-team-two-5-bbbbbbb-2\nRun 'h queue run' to start.\n", 0], [out, code]
    assert_equal %w[pr-fix-team-two-5-bbbbbbb-2.md pr-fix-team-two-5-bbbbbbb.md], queued
    job = File.read(File.join(queue_dir, 'pr-fix-team-two-5-bbbbbbb.md'))
    assert_equal "---\npr: team/two#5\npr_url: https://github.com/team/two/pull/5\nhead_sha: #{B}\n---\n/pr:fix https://github.com/team/two/pull/5\n",
                 job.lines.first(6).join
    assert_includes job, "Failing checks:\n- lint FAILURE https://ci.example.test/lint\n"
    assert_equal ["ERROR: fix: not tracked: team/one#9\n", 1], pr('fix', 'team/one#9')
    assert_equal ["Invalid selection: fix: run must be true or false\n", 1], pr('mfix', edit: edit_to("prs:\n- team/two#5\nrun: maybe\n"))

    assert_equal ["✓ team/two#5 untrack: removed from tracking\n", 0], pr('mrm', edit: edit_to("prs:\n- team/two#5\n"))
    assert_equal ["ERROR: untrack: not tracked: team/two#5\n", 1], pr('rm', 'team/two#5')
    rows = Sequel.sqlite(@db) { |db| db[:prs].select_map([:repo, :number, :tags_json]) }
    assert_equal [['team/one', 42, '["keep"]']], rows
  end

  def test_current_pr_commands_keep_grammar_flags_and_repository
    a = File.join(@dir, 'repo a')
    b = File.join(@dir, 'repo b')
    FileUtils.mkdir_p([a, b])
    prs = base_prs.merge('team/two#42' => { 'title' => 'two', 'state' => 'OPEN', 'head' => B, 'checks' => 1, 'reviews' => 0 })
    write_state(prs, current_by_dir: { File.realpath(a) => 'https://github.com/team/one/pull/42',
                                       File.realpath(b) => 'https://github.com/team/two/pull/42' })
    pr('track', 'team/one#42')
    pr('track', 'team/two#42')

    cpr = ->(*args, chdir: @dir) { run_bin('h-cpr', *args, chdir: chdir) }
    out, code = cpr.call('-C', b, 'merge', '--squash', '-d')
    assert_equal [['✓ team/two#42 merge'], 0], [outcome_lines(out), code]
    assert_equal [%w[pr merge https://github.com/team/two/pull/42 --squash --delete-branch]], gh_calls('merge')
    assert_equal ["team/two#42 now depends on: team/one#42\n", 0], cpr.call('dep', 'add', 'team/one#42', chdir: b)
    assert_equal ["Tagged team/one#42 with: urgent, later\n  Tags now: urgent, later\n", 0], cpr.call('-C', a, 'tag', 'urgent', 'later')
    assert_equal ["#{'https://github.com/team/two/pull/42'}", 0], cpr.call('link', chdir: b)
    out, code = cpr.call(chdir: a)
    assert_equal [['one team/one#42', 'state: OPEN', '✓ team/one#42 view'], 0], [outcome_lines(out), code]
    assert_equal ["ERROR: No PR for the current branch in #{@home}: no pull requests found for branch\n", 1], cpr.call('-C', @home, 'merge')
    assert_equal 1, gh_calls('merge').length
  end

  def test_foreground_checks_keep_gh_status_and_never_call_unknown_failing
    prs = base_prs.merge('team/six#6' => { 'title' => 'six', 'state' => 'OPEN', 'head' => A, 'checks' => 1, 'reviews' => 0,
                                           'error' => { 'checks' => 'Something went wrong' } })
    ready = File.join(@dir, 'checks.pid')
    write_state(prs, pr_checks: { 'team/one#42' => { 'exit' => 0, 'stdout' => '✓ build' },
                                  'team/two#5' => { 'exit' => 1, 'stdout' => 'X lint' },
                                  'team/six#6' => { 'exit' => 1, 'stdout' => 'error connecting to api.github.com' },
                                  'team/one#43' => { 'exit' => 0, 'sleep' => 30, 'ready_file' => ready } })

    assert_equal ["✓ build\nteam/one#42: checks passed (gh exit 0)\n", 0], pr('check', 'team/one#42')
    assert_equal ["X lint\nteam/two#5: checks failing (gh exit 1)\n", 1], pr('watch', 'team/two#5')
    assert_equal ["error connecting to api.github.com\nteam/six#6: checks unknown (gh exit 1)\n", 1], pr('fwatch', 'team/six#6')
    assert_equal [%w[pr checks https://github.com/team/one/pull/42], %w[pr checks https://github.com/team/two/pull/5 --watch],
                  %w[pr checks https://github.com/team/six/pull/6 --watch --fail-fast]], gh_calls('checks')
    assert_equal ['-message team/one#42 -title PR checks passed -open https://github.com/team/one/pull/42 -sound Basso',
                  '-message team/two#5: two -title PR checks failing -open https://github.com/team/two/pull/5 -sound Basso',
                  '-message team/six#6: six -title PR checks unknown -open https://github.com/team/six/pull/6 -sound Basso'], notes

    reader, writer = IO.pipe
    pid = Process.spawn(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/h-pr'), 'watch', 'team/one#43',
                        unsetenv_others: true, chdir: @dir, pgroup: true, out: writer, err: writer)
    writer.close
    Timeout.timeout(20) { sleep 0.05 until File.exist?(ready) && !File.read(ready).empty? }
    Process.kill('INT', -pid)
    _, status = Process.wait2(pid)
    assert_equal ["fake checks for team/one#43\nteam/one#43: interrupted\n", 130], [reader.read, status.exitstatus]
    assert_equal 3, notes.length
  end

  def test_monitor_cycles_survive_restart_without_duplicate_effects
    one = ->(**over) { { 'title' => 'one', 'state' => 'OPEN', 'head' => A, 'checks' => [PENDING], 'reviews' => 0 }.merge(over.transform_keys(&:to_s)) }
    write_state({ 'team/one#42' => one.call })
    pr('track', 'team/one#42')
    monitor = ->(*args) { run_bin('h-pr-monitor', '--once', *args).then { |out, code| [out.lines.map(&:chomp).drop(1), code] } }

    assert_equal [['team/one#42 checks baseline pending at aaaaaaa: baseline',
                   'team/one#42 review baseline review_required at aaaaaaa: baseline'], 0], monitor.call
    assert_equal [[], 0], monitor.call
    write_state({ 'team/one#42' => one.call(checks: [FAILED]) })
    assert_equal [['team/one#42 checks pending → failing at aaaaaaa: notified'], 0], monitor.call
    assert_equal [[], 0], monitor.call
    assert_empty queued

    write_state({ 'team/one#42' => one.call(checks: 250, fail: { 'checks' => { '2' => 'exit' } }) })
    assert_equal [['incomplete team/one#42: checks: page 2 failed: gh exited 1: HTTP 502: Bad Gateway (https://api.github.com/graphql)'], 0], monitor.call
    write_state({ 'team/one#42' => one.call(head: B, checks: [PENDING]) })
    assert_equal [['team/one#42 checks failing → pending at bbbbbbb: notified', 'team/one#42 fix baseline pending at bbbbbbb: baseline'], 0], monitor.call('-q')
    write_state({ 'team/one#42' => one.call(head: B, checks: [FAILED]) })
    assert_equal [['team/one#42 checks pending → failing at bbbbbbb: notified',
                   'team/one#42 fix pending → failing at bbbbbbb: queued pr-fix-team-one-42-bbbbbbb'], 0], monitor.call('-q')
    assert_equal [[], 0], monitor.call('-q')
    assert_equal ['pr-fix-team-one-42-bbbbbbb.md'], queued
    assert_equal ['-message team/one#42: one (aaaaaaa) -title PR checks failing -open https://github.com/team/one/pull/42 -sound Basso',
                  '-message team/one#42: one (bbbbbbb) -title PR checks pending -open https://github.com/team/one/pull/42 -sound Basso',
                  '-message team/one#42: one (bbbbbbb) -title PR checks failing -open https://github.com/team/one/pull/42 -sound Basso'], notes
    rows = Sequel.sqlite(@db) { |db| db[:pr_monitor_checkpoints].order(:channel).select_map([:channel, :head_sha, :state, :detail]) }
    assert_equal [['checks', B, 'failing', 'notified'], ['fix', B, 'failing', 'queued pr-fix-team-one-42-bbbbbbb'],
                  ['review', A, 'review_required', 'baseline']], rows
    assert_empty gh_calls('merge') + gh_calls('ready')
  end
end
