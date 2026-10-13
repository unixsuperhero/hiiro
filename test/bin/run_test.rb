require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'yaml'

# `h run`, `h js all`, and `h ch make` as subprocesses against fixture executables.
class RunCommandTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  ODD = ['a b.rb', "it's \"q\".rb", "new\nline.rb", '-lead.rb', '$(touch PWNED);x.rb', 'semi;&|.rb'].freeze

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('run-command-'))
    @home = File.join(@sandbox, 'home')
    @bin = File.join(@sandbox, 'bin')
    @repo = File.join(@sandbox, 'repo')
    @log = File.join(@sandbox, 'argv.log')
    @db = File.join(@sandbox, 'hiiro.db')
    FileUtils.mkdir_p([File.join(@home, '.config/hiiro'), @bin, @repo])
    # Every fixture appends {tool, cwd, argv} and fails when FIX_FAIL names "tool" or "tool:firstarg".
    recorder = <<~RUBY
      #!#{RbConfig.ruby}
      require 'json'
      $stdout.sync = true
      name = File.basename($0)
      File.open(#{@log.inspect}, 'a') { |f| f.puts JSON.generate('tool' => name, 'cwd' => Dir.pwd, 'argv' => ARGV) }
      puts "\#{name} \#{ARGV.first} ran"
      if name == 'sleeper'
        puts 'started'
        sleep 30
      end
      exit((ENV['FIX_FAIL'].to_s.split & [name, "\#{name}:\#{ARGV[0]}"]).empty? ? 0 : 3)
    RUBY
    %w[lint check yarn bun sleeper].each do |name|
      File.write(File.join(@bin, name), recorder)
      File.chmod(0o755, File.join(@bin, name))
    end
    system('git', 'init', '-q', '--initial-branch=main', @repo, exception: true)
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_run_passes_odd_filenames_as_exact_arguments_and_exits_with_the_first_failure
    ODD.each { |name| File.write(File.join(@repo, name), 'x') }
    File.write(File.join(@repo, 'notes.txt'), 'x')
    tools('lint' => { 'tool_type' => 'lint', 'file_extensions' => 'rb', 'argv' => ['lint', '--', '[FILENAMES]'] },
          'check' => { 'tool_type' => 'lint', 'file_extensions' => 'rb', 'argv' => ['check', '[FILENAMES]'] },
          'docs' => { 'tool_type' => 'lint', 'file_extensions' => 'md', 'argv' => ['lint', '[FILENAMES]'] })

    stdout, stderr, status = h('run', 'lint', env: { 'FIX_FAIL' => 'lint' }, chdir: @repo)

    assert_equal 3, status.exitstatus, stdout + stderr
    sorted = ODD.sort
    assert_equal [{ 'tool' => 'lint', 'cwd' => @repo, 'argv' => ['--', *sorted] },
                  { 'tool' => 'check', 'cwd' => @repo, 'argv' => sorted.map { |f| f.start_with?('-') ? "./#{f}" : f } }], log
    refute File.exist?(File.join(@repo, 'PWNED'))
    run_id = stdout[/--- run (\S+):/, 1]
    log_path = File.join(@home, ".local/share/hiiro/captures/validation/#{run_id}/01-lint.log")
    assert_equal ["--- run #{run_id}: 1 failed, 1 succeeded, 1 skipped",
                  "✗ lint   failed (exit 3)  log: #{log_path}",
                  "✓ check  exit 0",
                  "- docs   skipped: no matching files (md)",
                  "Queue these failures for an agent: h run queue #{run_id}"], stdout.lines(chomp: true).last(5)
    assert_equal "lint -- ran\n", File.read(log_path)
    assert_equal [File.join(@home, ".local/share/hiiro/captures/validation/#{run_id}")], Dir[File.join(@home, '.local/share/hiiro/captures/validation/*')]

    listing, = run_bin('h-capture', 'ls', chdir: @sandbox)
    assert_match(/0\. .*✗.*  lint  /, listing)
    queued, stderr, status = h('run', 'queue', chdir: @sandbox)
    assert status.success?, queued + stderr
    entry = File.join(@home, ".local/share/hiiro/queue/pending/validation-#{run_id}.md")
    assert_equal "Queued validation-#{run_id}: #{entry}\n", queued
    content = File.read(entry)
    assert content.start_with?("---\nvalidation_run: #{run_id}\n---\nValidation run #{run_id} has 1 failed command.\n\nTask: none\nRoot: #{@repo} (git)\n")
    assert_includes content, "  log: #{log_path}\n"
    assert_equal [], Dir[File.join(@home, '.local/share/hiiro/queue/{running,done,failed}/*')]
    assert_equal [], Dir[File.join(@home, '.local/share/hiiro/runs/*')]
  end

  def test_run_reports_git_failure_legacy_config_and_unknown_variation_without_running_anything
    tools('lint' => { 'tool_type' => 'lint', 'argv' => ['lint', '[FILENAMES]'] })
    outside = File.join(@sandbox, 'outside')
    FileUtils.mkdir_p(outside)
    _, stderr, status = h('run', chdir: outside)
    assert_equal [1, "ERROR: Not a git repository: #{outside}\n"], [status.exitstatus, stderr]
    _, stderr, status = h('run', '-v', 'nope', chdir: @repo)
    assert_equal [1, "ERROR: Unknown variation 'nope' for lint\n"], [status.exitstatus, stderr]
    _, stderr, status = h('run', 'test', chdir: @repo)
    assert_equal [1, "ERROR: No tools match tool_type test, file_type_group (any)\n"], [status.exitstatus, stderr]
    tools('lint' => { 'tool_type' => 'lint', 'command' => 'lint [FILENAMES]' })
    _, stderr, status = h('run', chdir: @repo)
    assert_equal 1, status.exitstatus
    assert_equal "ERROR: #{@home}/.config/hiiro/tools.yml uses the old `command:` format (lint); run `h run migrate` to convert it\n", stderr
    stdout, _, status = h('run', 'migrate', chdir: @repo)
    assert_equal 0, status.exitstatus
    assert_match(/\Alint: lint \[FILENAMES\]\n  -> \{"argv":\["lint","\[FILENAMES\]"\]\}\nBackup: .*tools\.yml\.\d{14}\.bak\n\z/, stdout)
    stdout, _, status = h('run', 'all', chdir: @repo)
    assert_equal 0, status.exitstatus, stdout
    assert_equal [{ 'tool' => 'lint', 'cwd' => @repo, 'argv' => [] }], log
  end

  def test_interrupt_stops_the_run_keeps_the_log_and_exits_130
    tools('sleeper' => { 'argv' => ['sleeper'] }, 'after' => { 'argv' => ['lint', 'after'] })
    reader, writer = IO.pipe
    pid = Process.spawn(env, RbConfig.ruby, '-rbundler/setup', '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'exe/h'), 'run', 'all',
                        chdir: @repo, out: writer, err: writer, in: File::NULL, pgroup: true, unsetenv_others: true)
    writer.close
    seen = +''
    seen << reader.readpartial(4096) until seen.include?("started\n")
    Process.kill('INT', -pid)
    seen << reader.read
    _, status = Process.wait2(pid)

    assert_equal 130, status.exitstatus, seen
    assert_equal ['sleeper'], log.map { |row| row['tool'] }
    assert_equal 1, seen.scan("started\n").size
    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal ['sleeper', 'interrupted', 130, 'INT'], row.values_at(:name, :outcome, :exit_status, :exit_signal)
    assert_match(/\Asleeper  ran\nstarted\n.*in `sleep': Interrupt\n/m, File.read(row[:path]))
    assert_match(/✗ sleeper  interrupted \(signal INT\)  log: #{Regexp.escape(row[:path])}\n- after    skipped: not run: interrupted\n/, seen)
  end

  def test_js_all_runs_every_check_in_the_package_directory_and_keeps_failed_logs
    package = File.join(@repo, 'web')
    FileUtils.mkdir_p(package)
    stdout, stderr, status = run_bin('h-js', 'all', env: { 'FIX_FAIL' => 'yarn:typecheck yarn:build' }, chdir: package)

    assert_equal 3, status.exitstatus, stdout + stderr
    assert_equal [%w[fmt], %w[typecheck], %w[test], %w[build]].map { |argv| { 'tool' => 'yarn', 'cwd' => package, 'argv' => argv } }, log
    run_id = stdout[/--- run (\S+):/, 1]
    dir = File.join(@home, ".local/share/hiiro/captures/validation/#{run_id}")
    assert_equal ['02-yarn-typecheck.log', '04-yarn-build.log'], Dir.children(dir).sort
    assert_equal "yarn typecheck ran\n", File.read(File.join(dir, '02-yarn-typecheck.log'))
    assert_equal ["--- run #{run_id}: 2 failed, 2 succeeded",
                  "✓ yarn fmt        exit 0",
                  "✗ yarn typecheck  failed (exit 3)  log: #{dir}/02-yarn-typecheck.log",
                  "✓ yarn test       exit 0",
                  "✗ yarn build      failed (exit 3)  log: #{dir}/04-yarn-build.log",
                  "Queue these failures for an agent: h run queue #{run_id}"], stdout.lines(chomp: true).last(6)
    assert_equal [], Dir[File.join(@home, 'notes/files/*')]
    rows = Sequel.sqlite(@db) { |db| db[:captures].where(run_id: run_id).order(:id).select_map([:name, :cwd, :outcome]) }
    assert_equal [['yarn typecheck', package, 'failed'], ['yarn build', package, 'failed']], rows
  end

  def test_ch_make_runs_the_build_adapter_and_checks_the_product
    tree = File.join(@home, 'work/ch/main')
    FileUtils.mkdir_p(tree)
    File.write(File.join(tree, 'package.json'), "{\n  \"scripts\": {\n    \"fmt\": \"x\"\n  }\n}\n")

    stdout, stderr, status = run_bin('h-ch', 'make', 'main', '--flag', env: { 'FIX_FAIL' => 'bun' }, chdir: @sandbox)
    assert_equal 3, status.exitstatus, stdout + stderr
    assert_equal [{ 'tool' => 'bun', 'cwd' => tree, 'argv' => ['run', 'dist', '--verbose', '--flag'] }], log
    assert_match(/✗ dist  failed \(exit 3\)  log: .*\/01-dist\.log\nQueue these failures for an agent: h run queue \S+\nFAIL: dist failed\n\z/, stdout)

    File.delete(@log)
    stdout, _, status = run_bin('h-ch', 'make', 'main', chdir: @sandbox)
    assert_equal 1, status.exitstatus
    assert stdout.end_with?("✓ dist  exit 0\nFAIL: dist did not produce release/CodeHiiro.app\n"), stdout
    FileUtils.mkdir_p(File.join(tree, 'release/CodeHiiro.app'))
    _, _, status = run_bin('h-ch', 'make', 'main', chdir: @sandbox)
    assert_equal 0, status.exitstatus
  end

  private

  def tools(config) = File.write(File.join(@home, '.config/hiiro/tools.yml'), YAML.dump(config))

  def log = File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) } : []

  def env(extra = {})
    { 'HOME' => @home, 'PATH' => "#{@bin}:#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'BUNDLE_PATH' => ENV['BUNDLE_PATH'], 'HIIRO_TEST_DB' => "sqlite://#{@db}",
      'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1' }.compact.merge(extra)
  end

  def h(*args, env: {}, chdir:) = run_path(File.join(ROOT, 'exe/h'), *args, env: env, chdir: chdir)

  def run_bin(bin, *args, env: {}, chdir:) = run_path(File.join(ROOT, 'bin', bin), *args, env: env, chdir: chdir)

  def run_path(path, *args, env:, chdir:)
    Open3.capture3(env(env), RbConfig.ruby, '-rbundler/setup', '-I', File.join(ROOT, 'lib'), path, *args,
                   chdir: chdir, stdin_data: '', unsetenv_others: true)
  end
end
