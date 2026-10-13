require 'test_helper'
require 'open3'
require 'rbconfig'
require 'digest'

# `h git commit` as a process: real git in a disposable repository, and a
# `claude` on PATH that is a fixed script, never a real provider.
class GitCommitCommandTest < Minitest::Test
  BIN = File.expand_path('../../bin/h-git', __dir__)
  LIB = File.expand_path('../../lib', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('h-git-commit-'))
    @repo = File.join(@root, 'repo')
    @path = File.join(@root, 'path')
    @home = File.join(@root, 'home')
    FileUtils.mkdir_p([@repo, @path, @home])
    @plan = File.join(@root, 'plan.json')
    @log = File.join(@root, 'prompt.txt')
    File.write(File.join(@path, 'claude'), <<~SH)
      #!/bin/sh
      cat > "#{@log}"
      printf '%s\\n' "$*" > "#{@log}.argv"
      [ -n "$PLAN_SIDE_EFFECT" ] && sh -c "$PLAN_SIDE_EFFECT"
      [ -n "$PLAN_STDERR" ] && echo "$PLAN_STDERR" >&2
      cat "#{@plan}"
      exit "${PLAN_EXIT:-0}"
    SH
    File.chmod(0o755, File.join(@path, 'claude'))
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    write('mixed.txt', "one\n")
    write('staged.txt', "a\n")
    write('deleted.txt', "gone\n")
    write('old.txt', "old name\n")
    git('add', '-A')
    git('commit', '-q', '-m', 'base')
    write('staged.txt', "a\nb\n")
    git('add', 'staged.txt')
    File.delete(File.join(@repo, 'deleted.txt'))
    git('mv', 'old.txt', 'new.txt')
    write('untracked.txt', "fresh\n")
    git('update-index', '-q', '--refresh')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def git(*args)
    out, err, status = Open3.capture3('git', *args, chdir: @repo, binmode: true)
    raise "git #{args.join(' ')}: #{err}" unless status.success?

    out
  end

  def write(path, content)
    File.binwrite(File.join(@repo, path), content)
  end

  def plan(*groups)
    File.write(@plan, JSON.generate(groups.map { |message, files| { 'message' => message, 'files' => files } }))
  end

  def cli(*args, input: '', env: {})
    environment = { 'HOME' => @home, 'PATH' => "#{@path}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
                    'HIIRO_TEST_DB' => 'sqlite::memory:' }.merge(env)
    out, status = Open3.capture2e(environment, RbConfig.ruby, '-I', LIB, BIN, 'commit', *args,
                                  stdin_data: input, chdir: @repo, unsetenv_others: true)
    [out, status.exitstatus]
  end

  def state
    files = Dir.glob('**/*', File::FNM_DOTMATCH, base: @repo).reject { |p| p.start_with?('.git') }.sort
    { index: File.binread(File.join(@repo, '.git/index')), staged: git('diff', '--cached', '--binary'),
      head: git('rev-parse', 'HEAD'), files: files.to_h { |p| [p, File.file?(File.join(@repo, p)) && Digest::SHA256.file(File.join(@repo, p)).hexdigest] } }
  end

  ALL = ['staged.txt', 'deleted.txt', 'new.txt', 'untracked.txt'].freeze

  def test_dry_run_prints_the_plan_and_changes_nothing
    write('mixed.txt', "one\ntwo\n")
    git('add', 'mixed.txt')
    write('mixed.txt', "one\ntwo\nthree\n")
    git('update-index', '-q', '--refresh')
    plan(['feat: rename', ['new.txt']], ['chore: rest', ['mixed.txt', 'staged.txt', 'deleted.txt', 'untracked.txt']])
    before = state

    out, code = cli('-n')

    assert_equal 0, code
    assert_equal before, state
    assert_equal <<~OUT, out
      Analyzing 5 changed file(s) with claude (sonnet)...

        [1] feat: rename
              - "new.txt"  (renamed from "old.txt")
        [2] chore: rest
              - "mixed.txt"  (staged+unstaged: whole file)
              - "staged.txt"
              - "deleted.txt"  (deleted)
              - "untracked.txt"

      These files have staged and unstaged changes; a commit takes the whole working file:
        "mixed.txt"

      (dry run — no commits made; index and working tree unchanged)
    OUT
    assert_equal "-p --model sonnet\n", File.read("#{@log}.argv")
    assert_includes File.read(@log), %({"path":"new.txt","status":"R","from":"old.txt"}\n{"path":"staged.txt","status":"M"}\n)
  end

  def test_invalid_plans_are_rejected_without_mutation
    before = state
    {
      [['feat: a', ['staged.txt', 'new.txt']]] => 'paths not assigned: "deleted.txt", "untracked.txt"',
      [['feat: a', ALL], ['feat: b', ['staged.txt']]] => 'paths assigned more than once: "staged.txt"',
      [['feat: a', ALL + ['ghost.txt']]] => 'unknown paths: "ghost.txt"'
    }.each do |groups, error|
      plan(*groups)
      out, code = cli('-y')
      assert_equal 1, code
      assert_includes out, "The planner returned an unusable plan; nothing was staged or committed:\n  - #{error}\n"
      assert_equal before, state
    end

    File.write(@plan, 'Sorry, I cannot help with that.')
    out, code = cli('-y')
    assert_equal [1, true], [code, out.include?('  - no JSON array in planner output')]
    assert_equal before, state
  end

  def test_planner_failure_cancellation_and_stale_plans_change_nothing
    plan(['feat: all', ALL])
    before = state

    out, code = cli('-y', env: { 'PLAN_EXIT' => '7', 'PLAN_STDERR' => 'quota exceeded' })
    assert_equal 1, code
    assert_includes out, 'ERROR: planner `claude -p --model sonnet` failed (exit 7): quota exceeded'
    assert_equal before, state

    out, code = cli(input: "n\n")
    assert_equal 1, code
    assert_includes out, "Create 1 commit(s)? [y/N] \nCancelled; nothing was committed.\n"
    assert_equal before, state

    _out, code = cli(input: '')
    assert_equal 1, code
    assert_equal before, state

    out, code = cli('-y', env: { 'PLAN_SIDE_EFFECT' => 'echo late >> untracked.txt' })
    assert_equal 1, code
    assert_includes out, 'HEAD, the index, or working files changed after planning; nothing was committed.'
    assert_equal before.slice(:index, :staged, :head), state.slice(:index, :staged, :head)
  end

  def test_partially_staged_files_need_whole_file_consent
    write('mixed.txt', "one\ntwo\n")
    git('add', 'mixed.txt')
    write('mixed.txt', "one\ntwo\nthree\n")
    git('update-index', '-q', '--refresh')
    plan(['feat: all', ALL + ['mixed.txt']])
    before = state

    out, code = cli('-y')
    assert_equal 1, code
    assert_includes out, 'Rerun with --whole-files'
    assert_equal before, state

    out, code = cli('-y', '--whole-files')
    assert_equal 0, code, out
    assert_equal "one\ntwo\nthree\n", git('show', 'HEAD:mixed.txt')
    assert_equal '', git('status', '--porcelain', '-uall')
  end

  def test_confirmed_two_group_plan_commits_exact_contents
    plan(['refactor: rename old to new', ['new.txt']], ["feat: rest\n\nWith a body.", ['staged.txt', 'deleted.txt', 'untracked.txt']])

    out, code = cli(input: "y\n")

    assert_equal 0, code, out
    assert_match(/^✓ \[1\] \h{12} refactor: rename old to new$/, out)
    assert_match(/^✓ \[2\] \h{12} feat: rest$/, out)
    assert_equal "feat: rest\n\nWith a body.\n\n", git('log', '-1', '--format=%B')
    assert_equal "R100\told.txt\tnew.txt\n", git('show', '--format=', '--name-status', '-M', 'HEAD~1')
    assert_equal "D\tdeleted.txt\nM\tstaged.txt\nA\tuntracked.txt\n", git('show', '--format=', '--name-status', 'HEAD')
    assert_equal "base\n", git('log', '-1', '--format=%s', 'HEAD~2')
    assert_equal '', git('status', '--porcelain', '-uall')
  end

  def test_failing_commit_hook_stops_later_groups_and_reports_progress
    hook = File.join(@repo, '.git/hooks/pre-commit')
    File.write(hook, "#!/bin/sh\necho 'lint failed' >&2\ngit diff --cached --name-only | grep -q '^staged.txt$' && exit 1\nexit 0\n")
    File.chmod(0o755, hook)
    plan(['refactor: rename', ['new.txt']], ['fix: staged', ['staged.txt']], ['chore: rest', ['deleted.txt', 'untracked.txt']])
    staged_blob = git('rev-parse', ':staged.txt')

    out, code = cli('-y')

    assert_equal 1, code
    assert_match(/^✓ \[1\] \h{12} refactor: rename$/, out)
    assert_includes out, "✗ [2] commit failed: git commit --quiet -F - failed (exit 1): lint failed\n"
    assert_includes out, "Stopped: 1 of 3 commit(s) made.\nCommits 2-3 were not made; their files keep their original staging.\n"
    refute_match(/^[✓✗] \[3\]/, out)
    assert_equal "refactor: rename\nbase\n", git('log', '--format=%s')
    assert_equal staged_blob, git('rev-parse', ':staged.txt')
    assert_equal "M  staged.txt\n D deleted.txt\n?? untracked.txt\n".lines.sort, git('status', '--porcelain', '-uall').lines.sort
  end
end
