require "test_helper"
require "open3"

class GitCommitPlanningTest < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir('commit-planning-'))
    @repo = File.join(@root, 'repo')
    FileUtils.mkdir_p(@repo)
    sh('init', '-q', '-b', 'main')
    sh('config', 'user.name', 'Fixture')
    sh('config', 'user.email', 'fixture@example.invalid')
    @git = Hiiro::Git::IndexGit.new(@repo)
  end

  def teardown
    FileUtils.chmod_R('u+rw', @root)
    FileUtils.remove_entry(@root)
  end

  def sh(*args, stdin: '')
    out, err, status = Open3.capture3('git', *args, stdin_data: stdin, chdir: @repo, binmode: true)
    raise "git #{args.join(' ')}: #{err}" unless status.success?

    out
  end

  def write(path, content)
    full = File.join(@repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content)
  end

  def commit_all(message = 'base')
    sh('add', '-A')
    sh('commit', '-q', '-m', message)
  end

  # Staged+unstaged same file, another staged file, deletion, staged rename, untracked.
  def mixed_fixture
    write('mixed.txt', "one\n")
    write('staged.txt', "a\n")
    write('deleted.txt', "gone\n")
    write('old.txt', "old name\n")
    commit_all
    write('mixed.txt', "one\nstaged\n")
    sh('add', 'mixed.txt')
    write('mixed.txt', "one\nstaged\nunstaged\n")
    write('staged.txt', "a\nb\n")
    sh('add', 'staged.txt')
    File.delete(File.join(@repo, 'deleted.txt'))
    sh('mv', 'old.txt', 'new.txt')
    write('untracked.txt', "fresh\n")
    sh('update-index', '-q', '--refresh')
  end

  def state
    { index: File.binread(File.join(@repo, '.git', 'index')), staged: sh('diff', '--cached', '--binary'),
      head: sh('rev-parse', 'HEAD'), status: sh('status', '--porcelain=v1', '-z', '-uall') }
  end

  def plan_json(*groups)
    JSON.generate(groups.map { |message, files| { 'message' => message, 'files' => files } })
  end

  def test_capture_lists_every_change_and_leaves_the_index_bytes
    mixed_fixture
    before = state

    change_set = Hiiro::Git::ChangeSet.capture(@git)

    assert_equal [
      { 'path' => 'deleted.txt', 'status' => 'D', 'source' => nil, 'staged' => false, 'unstaged' => true, 'untracked' => false, 'binary' => false },
      { 'path' => 'mixed.txt', 'status' => 'M', 'source' => nil, 'staged' => true, 'unstaged' => true, 'untracked' => false, 'binary' => false },
      { 'path' => 'new.txt', 'status' => 'R', 'source' => 'old.txt', 'staged' => true, 'unstaged' => false, 'untracked' => false, 'binary' => false },
      { 'path' => 'staged.txt', 'status' => 'M', 'source' => nil, 'staged' => true, 'unstaged' => false, 'untracked' => false, 'binary' => false },
      { 'path' => 'untracked.txt', 'status' => 'A', 'source' => nil, 'staged' => false, 'unstaged' => true, 'untracked' => true, 'binary' => false }
    ], change_set.changes.map(&:to_h)
    assert_equal ['mixed.txt'], change_set.partial.map(&:path)
    assert_includes change_set.diff, "+unstaged\n"
    assert_includes change_set.diff, "+fresh\n"
    assert_equal before, state
  end

  def test_capture_keeps_exact_unusual_names_and_binary_evidence
    write('a b.txt', "rename me\n")
    commit_all
    names = ["with space.txt", "quo\"te's.txt", "new\nline.txt", "-leading.txt", "star*.txt", "tab\there.txt"]
    names.each { |name| write(name, "#{name}\n") }
    write('blob.bin', "\x00\xFF\x00binary".b)
    sh('mv', 'a b.txt', "c'd.txt")

    change_set = Hiiro::Git::ChangeSet.capture(@git)

    assert_equal (names + ['blob.bin', "c'd.txt"]).sort, change_set.paths.sort
    assert_equal 'a b.txt', change_set.find("c'd.txt").source
    assert change_set.find('blob.bin').binary
    assert_includes change_set.diff, 'Binary files /dev/null and b/blob.bin differ'
  end

  def test_unborn_repository_is_planned_against_the_empty_tree
    write('first.txt', "1\n")
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    assert_equal [['first.txt', 'A', true]], change_set.changes.map { |c| [c.path, c.status, c.untracked] }
    assert_nil change_set.fingerprint[:head]
  end

  def test_validation_reports_every_problem_before_anything_runs
    mixed_fixture
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    raw = plan_json(['feat: a', ['mixed.txt', 'staged.txt', 'mixed.txt']], ['fix: b', ['staged.txt', 'nope.txt', 'old.txt']])

    validation = Hiiro::Git::CommitPlan.validate(raw, change_set)

    refute validation.valid?
    assert_nil validation.plan
    assert_equal ['nope.txt', 'old.txt'], validation.unknown
    assert_equal ['mixed.txt', 'staged.txt'], validation.duplicate
    assert_equal ['deleted.txt', 'new.txt', 'untracked.txt'], validation.missing
    assert_equal [
      'unknown paths: "nope.txt", "old.txt"',
      'paths assigned more than once: "mixed.txt", "staged.txt"',
      'paths not assigned: "deleted.txt", "new.txt", "untracked.txt"'
    ], validation.errors
  end

  def test_validation_rejects_bad_shapes
    mixed_fixture
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    errors = ->(raw) { Hiiro::Git::CommitPlan.validate(raw, change_set).errors }

    assert_equal ['no JSON array in planner output'], errors.('I could not do that.')
    assert_match(/\Aplanner output is not valid JSON/, errors.('[{"message": }]').first)
    assert_equal ['the plan has no commits'], errors.('[]')
    assert_equal ['commit 1 is not an object', 'commit 2 has no message', 'commit 3 needs a nonempty "files" array of strings'],
                 errors.('[1, {"message": " ", "files": ["mixed.txt"]}, {"message": "x", "files": [1]}]')
  end

  def test_valid_plan_keeps_groups_order_and_messages
    mixed_fixture
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    raw = "```json\n#{plan_json(['feat: rename', ['new.txt']], ["chore: rest\n\nbody", ['mixed.txt', 'staged.txt', 'deleted.txt', 'untracked.txt']])}\n```"

    plan = Hiiro::Git::CommitPlan.validate(raw, change_set).plan

    assert_equal [['feat: rename', ['new.txt']], ["chore: rest\n\nbody", ['mixed.txt', 'staged.txt', 'deleted.txt', 'untracked.txt']]],
                 plan.groups.map { |g| [g.message, g.paths] }
    assert_equal 'chore: rest', plan.groups.last.subject
  end

  def test_execution_commits_each_group_whole_and_leaves_index_matching_head
    mixed_fixture
    base = sh('rev-parse', 'HEAD').chomp
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    plan = Hiiro::Git::CommitPlan.validate(
      plan_json(['feat: rename', ['new.txt', 'staged.txt']], ['chore: rest', ['mixed.txt', 'deleted.txt', 'untracked.txt']]), change_set
    ).plan

    outcome = Hiiro::Git::CommitExecution.new(@git, change_set).call(plan)

    assert outcome.success?
    assert_equal [1, 2], outcome.completed.map(&:number)
    assert_equal "chore: rest\nfeat: rename\n", sh('log', '--format=%s', "#{base}..HEAD")
    assert_equal "R100\told.txt\tnew.txt\nM\tstaged.txt\n", sh('show', '--format=', '--name-status', '-M', 'HEAD~1')
    assert_equal "D\tdeleted.txt\nM\tmixed.txt\nA\tuntracked.txt\n", sh('show', '--format=', '--name-status', 'HEAD')
    assert_equal "one\nstaged\nunstaged\n", sh('show', 'HEAD:mixed.txt')
    assert_equal '', sh('status', '--porcelain', '-uall')
  end

  def test_commit_hook_failure_stops_and_keeps_later_staging
    mixed_fixture
    write('.git/hooks/pre-commit', "#!/bin/sh\ngit diff --cached --name-only | grep -q '^mixed.txt$' && exit 3\nexit 0\n")
    File.chmod(0o755, File.join(@repo, '.git/hooks/pre-commit'))
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    staged_before = sh('diff', '--cached', '--name-status', '--', 'mixed.txt', 'deleted.txt')
    mixed_index_blob = sh('rev-parse', ':mixed.txt')
    plan = Hiiro::Git::CommitPlan.validate(
      plan_json(['feat: rename', ['new.txt', 'staged.txt']], ['fix: mixed', ['mixed.txt']], ['chore: rest', ['deleted.txt', 'untracked.txt']]), change_set
    ).plan

    outcome = Hiiro::Git::CommitExecution.new(@git, change_set).call(plan)

    refute outcome.success?
    assert_equal [1], outcome.completed.map(&:number)
    assert_equal [2, 'commit'], [outcome.failure.number, outcome.failure.operation]
    assert_match(/git commit --quiet -F - failed \(exit 1\)/, outcome.failure.message)
    assert_equal "feat: rename\nbase\n", sh('log', '--format=%s')
    assert_equal staged_before, sh('diff', '--cached', '--name-status', '--', 'mixed.txt', 'deleted.txt')
    assert_equal mixed_index_blob, sh('rev-parse', ':mixed.txt')
    assert_equal " D deleted.txt\nMM mixed.txt\n?? untracked.txt\n", sh('status', '--porcelain', '-uall')
  end

  def test_add_failure_stops_before_any_later_group
    write('keep.txt', "k\n")
    commit_all
    write('keep.txt', "k2\n")
    write('locked.txt', "secret\n")
    write('later.txt', "later\n")
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    plan = Hiiro::Git::CommitPlan.validate(
      plan_json(['feat: keep', ['keep.txt']], ['feat: locked', ['locked.txt']], ['feat: later', ['later.txt']]), change_set
    ).plan
    File.chmod(0o000, File.join(@repo, 'locked.txt'))

    outcome = Hiiro::Git::CommitExecution.new(@git, change_set).call(plan)

    assert_equal [[1], 2, 'add'], [outcome.completed.map(&:number), outcome.failure.number, outcome.failure.operation]
    assert_match(/Permission denied/, outcome.failure.message)
    assert_equal "feat: keep\nbase\n", sh('log', '--format=%s')
    assert_equal "?? later.txt\n?? locked.txt\n", sh('status', '--porcelain', '-uall')
  end

  def test_execution_preserves_option_like_and_unusual_names
    write('a b.txt', "rename me\n")
    commit_all
    names = ["with space.txt", "quo\"te's.txt", "new\nline.txt", "-leading.txt", "star*.txt"]
    names.each { |name| write(name, "#{name}\n") }
    write('starfish.txt', "must stay out\n")
    sh('mv', 'a b.txt', "c'd.txt")
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    plan = Hiiro::Git::CommitPlan.validate(
      plan_json(['feat: odd', names], ['feat: rename', ["c'd.txt"]], ['feat: fish', ['starfish.txt']]), change_set
    ).plan

    outcome = Hiiro::Git::CommitExecution.new(@git, change_set).call(plan)

    assert outcome.success?
    assert_equal names.sort, sh('show', '--format=', '--name-only', '-z', 'HEAD~2').split("\0").sort
    assert_equal "R100\0a b.txt\0c'd.txt\0", sh('show', '--format=', '--name-status', '-z', '-M', 'HEAD~1')
    assert_equal "A\0starfish.txt\0", sh('show', '--format=', '--name-status', '-z', 'HEAD')
    assert_equal '', sh('status', '--porcelain', '-uall')
  end

  def test_planner_failure_and_missing_planner_raise
    mixed_fixture
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    bin = File.join(@root, 'bin')
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, 'claude'), "#!/bin/sh\ncat >/dev/null\necho 'rate limited' >&2\nexit 9\n")
    File.chmod(0o755, File.join(bin, 'claude'))
    planner = Hiiro::Git::CommitPlanner.new(model: 'sonnet')

    with_path("#{bin}:/usr/bin:/bin") do
      error = assert_raises(Hiiro::Git::CommitPlanner::Failed) { planner.call(change_set, cwd: @repo) }
      assert_equal 'planner `claude -p --model sonnet` failed (exit 9): rate limited', error.message
    end
    with_path('/usr/bin:/bin') do
      error = assert_raises(Hiiro::Git::CommitPlanner::Failed) { planner.call(change_set, cwd: @repo) }
      assert_match(/\Aplanner `claude -p --model sonnet` could not start: No such file or directory/, error.message)
    end
  end

  def test_prompt_lists_exact_paths_and_discloses_truncation
    mixed_fixture
    write('big.txt', "x" * (Hiiro::Git::ChangeSet::MAX_DIFF_BYTES + 10))
    change_set = Hiiro::Git::ChangeSet.capture(@git)
    prompt = Hiiro::Git::CommitPlanner.new(model: 'sonnet').prompt(change_set)

    assert_includes prompt, %({"path":"new.txt","status":"R","from":"old.txt"}\n)
    assert_includes prompt, 'Group by logical concern'
    assert_includes prompt, 'Unified diff (TRUNCATED — some changes omitted):'
    assert change_set.diff_truncated?
  end

  private

  def with_path(path)
    original = ENV['PATH']
    ENV['PATH'] = path
    yield
  ensure
    ENV['PATH'] = original
  end
end
