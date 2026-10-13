require 'test_helper'
require 'json'
require 'rbconfig'
require 'stringio'

class RunnerToolTest < Minitest::Test
  ODD = ['a b.rb', "it's \"q\".rb", "new\nline.rb", '-lead.rb', '$(touch PWNED);x.rb', 'semi;&|.rb'].freeze

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('runner-tool-'))
    @repo = File.join(@sandbox, 'repo')
    @log = File.join(@sandbox, 'argv.log')
    @bin = File.join(@sandbox, 'bin')
    FileUtils.mkdir_p([File.join(@repo, 'app'), @bin])
    git('init', '-q', '--initial-branch=main', @repo)
    File.write(File.join(@repo, 'app/tracked.rb'), "one\n")
    File.write(File.join(@repo, 'app/doomed.rb'), "gone\n")
    File.write(File.join(@repo, 'app/old name.rb'), "moving\n")
    File.write(File.join(@repo, 'top.rb'), "top\n")
    git('-C', @repo, 'add', '-A')
    commit('base')
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_dirty_change_set_lists_renames_deletions_and_odd_names_without_touching_the_index
    File.write(File.join(@repo, 'app/tracked.rb'), "two\n")
    File.delete(File.join(@repo, 'app/doomed.rb'))
    git('-C', @repo, 'mv', 'app/old name.rb', 'app/new name.rb')
    ODD.each { |name| File.write(File.join(@repo, 'app', name), 'x') }
    index = File.binread(File.join(@repo, '.git/index'))
    status = git_out('-C', @repo, 'status', '--porcelain=v1', '-z')

    changes = Hiiro::RunnerTool::ChangeSet.collect('dirty', directory: File.join(@repo, 'app'))

    assert_equal File.join(@repo, 'app'), changes.directory
    assert_equal @repo, changes.root
    assert_equal [['app/$(touch PWNED);x.rb', 'added', nil], ['app/-lead.rb', 'added', nil], ['app/a b.rb', 'added', nil],
                  ['app/doomed.rb', 'deleted', nil], ["app/it's \"q\".rb", 'added', nil], ["app/new\nline.rb", 'added', nil],
                  ['app/new name.rb', 'renamed', 'app/old name.rb'], ['app/semi;&|.rb', 'added', nil], ['app/tracked.rb', 'modified', nil]],
                 changes.changes.map { |c| [c.path, c.status, c.from] }.sort
    assert_equal ['$(touch PWNED);x.rb', '-lead.rb', 'a b.rb', "it's \"q\".rb", "new\nline.rb", 'new name.rb', 'semi;&|.rb', 'tracked.rb'],
                 changes.files.sort
    assert_equal ['app/doomed.rb'], changes.deleted.map(&:path)
    assert_equal index, File.binread(File.join(@repo, '.git/index'))
    assert_equal status, git_out('-C', @repo, 'status', '--porcelain=v1', '-z')
  end

  def test_branch_change_set_reads_committed_changes_against_main
    git('-C', @repo, 'checkout', '-q', '-b', 'feature')
    git('-C', @repo, 'mv', 'app/old name.rb', 'app/renamed.rb')
    git('-C', @repo, 'rm', '-q', 'app/doomed.rb')
    File.write(File.join(@repo, 'app', "new\nline.rb"), 'x')
    git('-C', @repo, 'add', '-A')
    commit('feature')
    File.write(File.join(@repo, 'top.rb'), "uncommitted\n")

    changes = Hiiro::RunnerTool::ChangeSet.collect('branch', directory: @repo)

    assert_equal [['app/doomed.rb', 'deleted', nil], ["app/new\nline.rb", 'added', nil], ['app/renamed.rb', 'renamed', 'app/old name.rb']],
                 changes.changes.map { |c| [c.path, c.status, c.from] }.sort
    assert_equal ["app/new\nline.rb", 'app/renamed.rb'], changes.files.sort
  end

  def test_git_failures_raise_instead_of_reading_as_no_changes
    outside = File.join(@sandbox, 'outside')
    FileUtils.mkdir_p(outside)
    error = assert_raises(Hiiro::Error) { Hiiro::RunnerTool::ChangeSet.collect('dirty', directory: outside) }
    assert_equal "Not a git repository: #{outside}", error.message
    git('-C', @repo, 'branch', '-q', '-m', 'main', 'trunk')
    error = assert_raises(Hiiro::Error) { Hiiro::RunnerTool::ChangeSet.collect('branch', directory: @repo) }
    assert_equal "No merge base between HEAD and main in #{@repo}", error.message
  end

  def test_templates_expand_files_as_exact_arguments_and_refuse_unsupported_forms
    files = ['-lead.rb', 'a b.rb']
    plain = Hiiro::RunnerTool::Template.new('t', argv: ['lint', '-q', '[FILENAMES]'])
    assert_equal ['lint', '-q', './-lead.rb', 'a b.rb'], plain.spec(files, cwd: @repo).argv
    terminated = Hiiro::RunnerTool::Template.new('t', argv: ['lint', '--', '[FILENAMES]', '--after'])
    assert_equal ['lint', '--', '-lead.rb', 'a b.rb', '--after'], terminated.spec(files, cwd: @repo).argv
    assert_equal ['lint', '--', '--after'], terminated.spec(nil, cwd: @repo).argv
    shell = Hiiro::RunnerTool::Template.new('t', shell: 'lint "$@" | tee out')
    assert_equal ['/bin/bash', '-c', 'lint "$@" | tee out', 'hiiro-shell', '-lead.rb', 'a b.rb'], shell.spec(files, cwd: @repo).argv
    assert_equal @repo, shell.spec(files, cwd: @repo).cwd

    {
      { argv: ['lint', '--files=[FILENAMES]'] } => 'Tool t: unsupported template element "--files=[FILENAMES]"; [FILENAMES] must be a whole argv element',
      { argv: ['lint', '[FILES]'] } => 'Tool t: unsupported template element "[FILES]"; [FILENAMES] must be a whole argv element',
      { argv: ['[FILENAMES]'] } => 'Tool t: argv cannot start with [FILENAMES]',
      { argv: ['a', '[FILENAMES]', '[FILENAMES]'] } => 'Tool t: [FILENAMES] may appear once',
      { argv: [] } => 'Tool t: argv must be a non-empty list of strings',
      { shell: 'lint [FILENAMES]' } => 'Tool t: shell recipes receive files as "$@"; [FILENAMES] is not substituted into shell text',
      { shell: ' ' } => 'Tool t: shell text cannot be blank',
    }.each do |form, message|
      assert_equal message, assert_raises(Hiiro::Error) { Hiiro::RunnerTool::Template.new('t', **form) }.message
    end
    assert_equal 'Tool t: a command is `argv: [...]` or `shell: TEXT`',
                 assert_raises(Hiiro::Error) { Hiiro::RunnerTool::Template.from('t', { 'argv' => ['a'], 'shell' => 'b' }) }.message
  end

  def test_legacy_conversion_keeps_meaning_or_leaves_the_command_for_a_manual_edit
    convert = Hiiro::RunnerTool::LegacyConversion.method(:convert)
    assert_equal({ 'argv' => ['rubocop', '-A', '[FILENAMES]'] }, convert.('rubocop -A [FILENAMES]'))
    assert_equal({ 'argv' => ['yarn', 'jest'] }, convert.('yarn jest'))
    assert_equal({ 'shell' => 'bundle exec rspec "$@" && echo ok' }, convert.('bundle exec rspec [FILENAMES] && echo ok'))
    assert_equal({ 'shell' => 'FOO=1 lint "$@"' }, convert.('FOO=1 lint [FILENAMES]'))
    assert_equal({ 'shell' => "printf '%s\\n' \"$@\" > out" }, convert.("printf '%s\\n' [FILENAMES] > out"))
    assert_nil convert.('lint "[FILENAMES]"')
    assert_nil convert.('lint --files=[FILENAMES]')
    assert_nil convert.('lint [OTHER] | cat')
  end

  def test_migrate_rewrites_legacy_tools_with_a_backup_and_the_runner_refuses_legacy_until_then
    config = File.join(@sandbox, 'tools.yml')
    original = <<~YAML
      rubocop:
        tool_type: lint
        command: rubocop [FILENAMES]
        file_type_group: ruby
        file_extensions: rb
        variations:
          fix: rubocop -A [FILENAMES]
          quick: rubocop --only Style [FILENAMES] | head
      quoted:
        tool_type: test
        command: lint "[FILENAMES]"
    YAML
    File.write(config, original)
    runner = Hiiro::RunnerTool.new(config_file: config, context: context_for(@repo))
    error = assert_raises(Hiiro::Error) { runner.steps(out: StringIO.new) }
    assert_equal "#{config} uses the old `command:` format (rubocop, quoted); run `h run migrate` to convert it", error.message

    report = runner.migrate_config!

    backup = report.first[:backup]
    assert_match(/\A#{Regexp.escape(config)}\.\d{14}\.bak\z/, backup)
    assert_equal original, File.read(backup)
    assert_equal [['rubocop', nil, { 'argv' => %w[rubocop [FILENAMES]] }],
                  ['rubocop', 'fix', { 'argv' => %w[rubocop -A [FILENAMES]] }],
                  ['rubocop', 'quick', { 'shell' => 'rubocop --only Style "$@" | head' }],
                  ['quoted', nil, nil]], report.map { |row| row.values_at(:tool, :variation, :to) }
    assert_equal({ 'rubocop' => { 'tool_type' => 'lint', 'argv' => %w[rubocop [FILENAMES]], 'file_type_group' => 'ruby', 'file_extensions' => 'rb',
                                  'variations' => { 'fix' => { 'argv' => %w[rubocop -A [FILENAMES]] },
                                                    'quick' => { 'shell' => 'rubocop --only Style "$@" | head' } } },
                   'quoted' => { 'tool_type' => 'test', 'command' => 'lint "[FILENAMES]"' } }, YAML.safe_load_file(config))
    assert_equal 'rubocop', runner.steps(tool_type: 'lint', change_set: 'all', out: StringIO.new).first.name
    assert_raises(Hiiro::Error) { runner.steps(tool_type: 'test', change_set: 'all', out: StringIO.new) }
  end

  def test_steps_report_selection_outcomes_before_anything_runs
    config = File.join(@sandbox, 'tools.yml')
    File.write(config, YAML.dump('lint' => { 'tool_type' => 'lint', 'file_extensions' => 'rb', 'argv' => ['lint', '[FILENAMES]'],
                                             'variations' => { 'fix' => { 'argv' => ['lint', '--fix', '[FILENAMES]'] } } },
                                 'style' => { 'tool_type' => 'lint', 'file_extensions' => 'css', 'argv' => ['style', '[FILENAMES]'] }))
    File.write(File.join(@repo, 'app/tracked.rb'), "changed\n")
    File.delete(File.join(@repo, 'app/doomed.rb'))
    runner = Hiiro::RunnerTool.new(config_file: config, context: context_for(@repo, File.join(@repo, 'app')))
    out = StringIO.new

    steps = runner.steps(tool_type: 'lint', out: out)
    assert_equal "dirty: 1 file under #{@repo}/app (1 deleted, not passed)\n", out.string
    assert_equal [['lint', ['lint', 'tracked.rb'], File.join(@repo, 'app'), nil], ['style', nil, nil, 'no matching files (css)']],
                 steps.map { |s| [s.name, s.spec&.argv, s.spec&.cwd, s.skip_reason] }
    assert_equal [['lint', ['lint', '--fix', 'tracked.rb'], nil], ['style', nil, "no variation 'fix'"]],
                 runner.steps(variation: 'fix', out: out).map { |s| [s.name, s.spec&.argv, s.skip_reason] }
    assert_equal "Unknown variation 'nope' for lint, style", assert_raises(Hiiro::Error) { runner.steps(variation: 'nope', out: out) }.message
    assert_equal 'No tools match tool_type test, file_type_group (any)', assert_raises(Hiiro::Error) { runner.steps(tool_type: 'test', out: out) }.message
  end

  def test_execute_runs_every_step_retains_failures_with_context_and_aggregates_truthfully
    fixture('fail', "puts 'fail out'; warn 'fail err'; exit 3")
    fixture('pass', "puts 'pass out'")
    context = context_for(@repo, File.join(@repo, 'app'))
    steps = [
      step('fail', [File.join(@bin, 'fail'), 'a b']),
      step('missing', [File.join(@bin, 'nope')]),
      Hiiro::RunnerTool::Step.new('skip', nil, 'no matching files (css)'),
      step('pass', [File.join(@bin, 'pass')]),
    ]
    out = StringIO.new
    err = StringIO.new
    code = Hiiro::RunnerTool.execute(steps, context: context, run_id: 'run-1', out: out, err: err, stdin: File::NULL)

    assert_equal 3, code
    log_dir = File.join(Hiiro::RunnerTool.log_dir, 'run-1')
    assert_equal ['01-fail.log', '02-missing.log'], Dir.children(log_dir).sort
    assert_equal "fail out\nfail err\n", File.read(File.join(log_dir, '01-fail.log'))
    assert_equal "#{@bin}/nope: No such file or directory - #{@bin}/nope\n", File.read(File.join(log_dir, '02-missing.log'))
    rows = Hiiro::Capture.where(run_id: 'run-1').order(:id).all
    assert_equal [['fail', 'failed', 3, nil, 'validation', File.join(@repo, 'app')], ['missing', 'failed', 127, nil, 'validation', File.join(@repo, 'app')]],
                 rows.map { |r| [r.name, r.outcome, r.exit_status, r.exit_signal, r.source, r.cwd] }
    assert_equal({ 'task' => nil, 'task_source' => nil, 'app' => nil, 'app_directory' => nil, 'root' => @repo, 'root_source' => 'override',
                   'directory' => File.join(@repo, 'app'), 'directory_source' => 'override' }, JSON.parse(rows.first.context_json))
    assert_equal "#{File.join(@bin, 'fail')} a\\ b", rows.first.command
    assert_includes out.string, "fail out\nfail err\n"
    assert_includes out.string, "pass out\n"
    assert_equal ["--- run run-1: 2 failed, 1 succeeded, 1 skipped",
                  "✗ fail     failed (exit 3)  log: #{log_dir}/01-fail.log",
                  "✗ missing  failed (exit 127)  log: #{log_dir}/02-missing.log",
                  "- skip     skipped: no matching files (css)",
                  "✓ pass     exit 0",
                  "Queue these failures for an agent: h run queue run-1"], out.string.lines(chomp: true).last(6)
    assert_equal "#{@bin}/nope: No such file or directory - #{@bin}/nope\n", err.string

    assert_equal 0, Hiiro::RunnerTool.execute([step('pass', [File.join(@bin, 'pass')])], context: context, run_id: 'run-2', out: StringIO.new, stdin: File::NULL)
    refute File.exist?(File.join(Hiiro::RunnerTool.log_dir, 'run-2', '01-pass.log'))
    assert_equal 0, Hiiro::Capture.where(run_id: 'run-2').count
  end

  def test_queue_job_names_the_retained_logs_and_keeps_the_task_association
    task = Struct.new(:name, :primary_directory, :tree, :session).new('alpha', @repo, nil, nil)
    context = Hiiro::TaskLocation.for(task, invocation_directory: @repo, terminal: Hiiro::Herdr::Location.new)
                                 .with_directory(File.join(@repo, 'app'), source: :override)
    fixture('fail', 'exit 4')
    Hiiro::RunnerTool.execute([step('fail', [File.join(@bin, 'fail')])], context: context, run_id: 'run-q', out: StringIO.new, stdin: File::NULL)
    capture = Hiiro::Capture.where(run_id: 'run-q').first

    job = Hiiro::RunnerTool::QueueJob.for_run('run-q')

    assert_equal 'validation-run-q', job.name
    assert_equal <<~MD.chomp, job.content
      ---
      validation_run: run-q
      task_name: alpha
      dir: app
      ---
      Validation run run-q has 1 failed command.

      Task: alpha (explicit)
      Root: #{@repo} (primary)
      Directory: #{@repo}/app (override)

      - fail: failed (exit 4)
        command: #{@bin}/fail
        cwd: #{@repo}/app
        log: #{Hiiro::RunnerTool.log_dir}/run-q/01-fail.log
        ran: #{capture.started_at} .. #{capture.finished_at}

      Read each log, fix the cause, and re-run the same commands in the same directory to confirm.
    MD
    assert_equal 'No retained failures for run nope', assert_raises(Hiiro::Error) { Hiiro::RunnerTool::QueueJob.for_run('nope') }.message
  end

  private

  def context_for(root, directory = root)
    Hiiro::TaskLocation.for(nil, root: root, invocation_directory: root, terminal: Hiiro::Herdr::Location.new)
                       .with_directory(directory, source: :override)
  end

  def step(name, argv) = Hiiro::RunnerTool::Step.new(name, Hiiro::CommandSpecification.new(*argv, cwd: File.join(@repo, 'app')), nil)

  def fixture(name, code)
    path = File.join(@bin, name)
    File.write(path, "#!#{RbConfig.ruby}\n$stdout.sync = true\n#{code}\n")
    File.chmod(0o755, path)
  end

  def commit(message)
    git('-C', @repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'core.hooksPath=/dev/null',
        'commit', '-q', '-m', message)
  end

  def git(*args) = assert(system('git', *args), "git #{args.join(' ')} failed")

  def git_out(*args) = IO.popen(['git', *args], &:read)
end
