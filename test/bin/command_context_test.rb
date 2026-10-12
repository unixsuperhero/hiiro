require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'shellwords'

class CommandContextTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  PRELOAD = <<~'RUBY'
    class Hiiro
      class Config
        def self.plugin_files = []
      end
    end
    require 'hiiro'
    require File.join(ENV.fetch('CONTEXT_REPO'), 'plugins/pins')
    Hiiro::DB.setup!
  RUBY
  MARKER = <<~'RUBY'
    require 'json'
    File.write(ENV.fetch('CONTEXT_MARKER'), JSON.generate({cwd: Dir.pwd, argv: ARGV,
      files: ARGV.reject { |arg| arg.start_with?('-') }.select { |arg| File.file?(arg) }.to_h { |arg| [File.realpath(arg), File.read(arg)] }}))
  RUBY

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('hiiro-command-context-'))
    @home = File.join(@sandbox, 'home')
    @outside = File.join(@sandbox, 'outside')
    @config = File.join(@home, '.config/hiiro')
    @git_root = File.join(@sandbox, 'git-root')
    @task_root = File.join(@sandbox, 'task-root')
    @marker = File.join(@sandbox, 'marker.json')
    @db_path = File.join(@sandbox, 'data.sqlite3')
    @preload = File.join(@sandbox, 'preload.rb')
    @program = File.join(@sandbox, 'observe.rb')
    @editor = File.join(@sandbox, 'observe-editor')
    FileUtils.mkdir_p([@outside, @config, File.join(@home, 'proj')])
    [@git_root, @task_root].each do |root|
      FileUtils.mkdir_p([File.join(root, 'apps/api/subdir'), File.join(root, 'apps/admin')])
      git('init', '-q', root)
      File.write(File.join(root, 'apps/api/entry.rb'), "#{File.basename(root)} file\n")
      git('-C', root, 'add', '.')
    end
    File.write(@preload, PRELOAD)
    File.write(@program, MARKER)
    File.write(@editor, "#!#{RbConfig.ruby}\n" + MARKER)
    File.chmod(0o755, @editor)
    script('nil')
    @db = Sequel.sqlite(@db_path)
    @db[:tasks].insert(id: 41, name: 'alpha', session: 'alpha', primary_directory: @task_root, status: 'active')
    @db[:tasks].insert(id: 42, name: 'alpine', session: 'alpine', status: 'active')
    @db[:tasks].insert(id: 43, name: 'notes', session: 'notes', status: 'active')
    %w[alpha alpine notes].each { |name| FileUtils.mkdir_p(File.join(@home, 'notes/work', name)) }
    @db[:apps].insert(name: 'api', path: 'apps/api')
    @db[:apps].insert(name: 'api-admin', path: 'apps/admin')
    @db[:projects].insert(name: 'demo', path: @git_root)
    @db[:projects].insert(name: 'demo-extra', path: @task_root)
    File.write(File.join(@config, 'tools.yml'), {'observe' => {'command' => [RbConfig.ruby, @program].shelljoin, 'tool_type' => 'test'}}.to_yaml)
    File.write(File.join(@config, 'app_files.yml'), {'api' => ['apps/api/entry.rb']}.to_yaml)
  end

  def teardown
    @db&.disconnect
    FileUtils.remove_entry(@sandbox) if @sandbox && File.exist?(@sandbox)
  end

  def test_task_current_and_path_exact_prefix_dot_and_optional_app
    assert_equal "alpha\n", command('t', 'current', '-t', 'alpha')
    assert_equal "alpha\n", command('t', 'current', '-t', 'alph')
    assert_equal "alpha\n", command('t', 'current', '.', cwd: @task_root)
    assert_equal "#{@task_root}\n", command('t', 'path', '-t', 'alpha')
    assert_equal "#{@task_root}/apps/api\n", command('t', 'path', '-t', 'alpha', 'api')
    assert_equal "#{@home}/notes/work/notes\n", command('t', 'path', '-t', 'notes')
  end

  def test_app_path_uses_git_root_without_task_and_task_root_when_current
    nested = File.join(@git_root, 'apps/api/subdir')
    assert_equal "..\n", command('h-app', 'path', 'api', cwd: nested)
    assert_equal "#{@git_root}/apps/api\n", command('h-app', 'abspath', 'api', cwd: nested)
    assert_equal "#{@git_root}/apps/api\n", command('h', 'app', 'abspath', 'api', cwd: nested)
    assert_equal "..\n", command('h', 'app', 'path', 'api', cwd: nested)
    assert_equal "#{@git_root}/apps/admin\n", command('h-app', 'abspath', 'api-a', cwd: nested)
    assert_equal "../../..\n", command('h-app', 'path', cwd: nested)
    assert_equal "#{@task_root}/apps/api\n", command('h-app', 'abspath', 'api', cwd: @task_root)
    assert_equal "#{@task_root}\n", command('h-app', 'abspath', cwd: @task_root)
  end

  def test_optional_context_provenance_and_real_owner_values
    actual = context('Hiiro::CurrentTask.new(task: "alpha", pin: false).context(app: "api")', cwd: @git_root)
    assert_equal({'task' => [41, 'alpha'], 'app' => 'api', 'project' => nil,
      'task_source' => 'explicit', 'source' => 'app', 'root' => @task_root,
      'directory' => File.join(@task_root, 'apps/api')}, actual)
    inferred = context('Hiiro::CurrentTask.new(pin: false).context', cwd: @task_root)
    assert_equal [[41, 'alpha'], 'directory', 'primary', @task_root], inferred.values_at('task', 'task_source', 'source', 'directory')
    taskless = context('Hiiro::CurrentTask.new(pin: false).context', cwd: File.join(@git_root, 'apps/api'))
    assert_equal [nil, nil, 'git', @git_root], taskless.values_at('task', 'task_source', 'source', 'directory')
    override = context("Hiiro::CurrentTask.new(task: 'alpha', pin: false).context(override: #{@git_root.inspect})")
    assert_equal [[41, 'alpha'], 'explicit', 'override', @git_root], override.values_at('task', 'task_source', 'source', 'directory')
    command('t', 'use', 'alpha')
    pinned = context('Hiiro::CurrentTask.new.context')
    assert_equal [[41, 'alpha'], 'pin', 'primary', @task_root], pinned.values_at('task', 'task_source', 'source', 'directory')
    command('t', 'current', cwd: @task_root)
  end

  def test_taskless_project_and_home_contexts_do_not_create_tasks
    before = domain_rows
    assert_equal @git_root, command('h-project', 'path', 'demo')
    assert_equal @task_root, command('h-project', 'path', 'demo-e')
    assert_equal @home, command('h-home', 'path').strip
    assert_equal File.join(@home, 'proj'), command('h-project', 'path')
    project = context('Hiiro::Projects.new.context("demo")')
    assert_equal [nil, 'demo', 'project', @git_root], project.values_at('task', 'project', 'source', 'directory')
    assert_equal before, domain_rows
  end

  def test_missing_ambiguous_absent_and_stale_selectors_leave_store_and_marker_unchanged
    before = domain_rows
    failure('t', 'current', /No current task/)
    failure('t', 'sh', '-t', 'missing', RbConfig.ruby, @program, /Task not found/)
    failure('t', 'sh', '-t', 'al', RbConfig.ruby, @program, /Ambiguous task/)
    failure('h-app', 'run', '--app', 'missing', 'all', /App.*not found|No app matches/i, cwd: @git_root)
    failure('h-app', 'run', '--app', 'ap', 'all', /Ambiguous app/i, cwd: @git_root)
    failure('h-project', 'path', 'missing', /not found/i)
    failure('h-project', 'path', 'dem', /Ambiguous project/i)
    assert_equal before, domain_rows
    refute File.exist?(@marker)
    @db[:pins].insert(command: 't', key: 'current_task', value_json: '999', value_format: 'json')
    stale = domain_rows
    failure('t', 'current', /Saved task no longer exists/)
    assert_equal stale, domain_rows
    assert_equal "#{@git_root}/apps/api\n", command('h-app', 'abspath', 'api', cwd: @git_root)
    assert_equal "alpha\n", command('t', 'current', '-t', 'alpha')
  end

  def test_realpath_directory_inference_overlap_and_app_escape
    link = File.join(@sandbox, 'task-link')
    File.symlink(@task_root, link)
    assert_equal "alpha\n", command('t', 'current', cwd: File.join(link, 'apps/api'))
    @db[:task_resources].insert(task_id: 42, kind: 'directory', target: File.join(@task_root, 'apps'))
    before = domain_rows
    failure('t', 'current', /Ambiguous directory task/, cwd: File.join(link, 'apps/api'))
    failure('h-app', 'run', '--app', 'api', 'all', /Ambiguous directory task/, cwd: File.join(link, 'apps/api'))
    assert_equal "alpha\n", command('t', 'current', '-t', 'alpha', cwd: File.join(link, 'apps/api'))
    assert_equal before, domain_rows
    escape = File.join(@task_root, 'apps/escaped')
    File.symlink(@git_root, escape)
    @db[:apps].insert(name: 'escaped', path: 'apps/escaped')
    failure('h-app', 'run', '--app', 'escaped', 'all', /escapes root/, cwd: @task_root)
    refute File.exist?(@marker)
  end

  def test_root_task_and_app_runner_cwds_agree_with_paths
    command('h', 'run', 'all', cwd: File.join(@git_root, 'apps/api'))
    assert_equal @git_root, marker.fetch('cwd')
    command('h', 'run', 'all', cwd: File.join(@task_root, 'apps/api'))
    assert_equal @task_root, marker.fetch('cwd')
    command('h-app', 'run', '--app', 'api', 'all', cwd: @task_root)
    assert_equal command('h-app', 'abspath', 'api', cwd: @task_root).strip, marker.fetch('cwd')
    command('t', 'run', '-t', 'alpha', 'all', cwd: @git_root)
    assert_equal @task_root, marker.fetch('cwd')
    command('t', 'run', '-t', 'alpha', '--app', 'api', 'all', cwd: @git_root)
    assert_equal File.join(@task_root, 'apps/api'), marker.fetch('cwd')
  end

  def test_scoped_git_and_runner_file_discovery_ignore_invocation_repository
    assert_equal @task_root, script("puts Hiiro::Git.new(nil, #{@task_root.inspect}).root", cwd: @git_root).strip
    File.write(File.join(@config, 'tools.yml'), {'observe' => {'command' => [RbConfig.ruby, @program].shelljoin + ' [FILENAMES]', 'tool_type' => 'test', 'file_extensions' => 'rb'}}.to_yaml)
    command('t', 'run', '-t', 'alpha', '--app', 'api', 'dirty', cwd: @git_root)
    assert_equal({'cwd' => File.join(@task_root, 'apps/api'), 'argv' => ['entry.rb'],
      'files' => {File.join(@task_root, 'apps/api/entry.rb') => "task-root file\n"}}, marker)
  end

  def test_explicit_directory_override_and_missing_directory_fail_strictly
    assert_equal "#{@git_root}\n", command('t', 'path', '-t', 'alpha', '--directory', @git_root)
    missing = File.join(@sandbox, 'missing')
    @db[:projects].insert(name: 'gone', path: missing)
    before = domain_rows
    failure('t', 'path', '-t', 'alpha', '--directory', missing, /Directory does not exist/)
    failure('h-project', 'sh', 'gone', RbConfig.ruby, @program, /Directory does not exist/)
    failure('h-app', 'run', '--app', /Missing app name/i, cwd: @git_root)
    assert_equal before, domain_rows
    refute File.exist?(@marker)
  end

  def test_taskless_project_and_home_shells_preserve_native_argv
    before = domain_rows
    payload = ['--resume', 'session one', 'alpha']
    command('h-project', 'sh', 'demo', RbConfig.ruby, @program, *payload)
    assert_equal [@git_root, payload], marker.values_at('cwd', 'argv')
    command('h-home', 'sh', RbConfig.ruby, @program, *payload)
    assert_equal [@home, payload], marker.values_at('cwd', 'argv')
    assert_equal before, domain_rows
  end

  def test_missing_app_directory_does_not_launch_runner
    @db[:apps].insert(name: 'gone', path: 'apps/gone')
    File.write(@marker, 'unchanged')
    before = domain_rows
    failure('h-app', 'run', '--app', 'gone', 'all', /Directory does not exist/, cwd: @git_root)
    assert_equal 'unchanged', File.read(@marker)
    assert_equal before, domain_rows
  end

  def test_missing_task_code_directory_never_falls_back_to_notes_home
    FileUtils.remove_entry(@task_root)
    before = domain_rows
    File.write(@marker, 'unchanged')
    failure('t', 'sh', '-t', 'alpha', RbConfig.ruby, @program, /Directory does not exist/)
    failure('t', 'run', '-t', 'alpha', 'all', /Directory does not exist/)
    assert_equal 'unchanged', File.read(@marker)
    assert_equal before, domain_rows
  end

  def test_actual_native_shell_receives_payload_flags_words_and_binary_output
    payload = ['--resume', 'native-session', '--session-id', 'session value', 'alpha', '-t', 'payload-task', '--', "quotes' and spaces"]
    command('t', 'sh', '-t', 'alpha', RbConfig.ruby, @program, *payload, cwd: @git_root)
    assert_equal({'cwd' => @task_root, 'argv' => payload, 'files' => {}}, marker)
    command('t', 'sh', '.', RbConfig.ruby, @program, 'alpha', cwd: @task_root)
    assert_equal ['alpha'], marker.fetch('argv')
    assert_equal "\x00\xFF\n".b, command('t', 'sh', '-t', 'alpha', RbConfig.ruby, '-e', 'STDOUT.binmode; STDOUT.write([0,255,10].pack("C*"))').b
  end

  def test_queue_pane_dir_applies_task_app_dir_and_taskless_base
    prompt = prompt_file('task_name' => 'alpha', 'app' => 'api', 'dir' => 'subdir')
    assert_equal File.join(@task_root, 'apps/api/subdir'), command('h', 'queue', 'pane-dir', prompt, @git_root)
    plain = prompt_file({})
    assert_equal @git_root, command('h', 'queue', 'pane-dir', plain, @git_root)
    provenance = script("q = Hiiro::Queue.new(context: Hiiro::CurrentTask.new(pin: false).context); c = q.resolve_prompt_context(q.read_prompt(#{prompt.inspect})); puts JSON.generate([c.task.id, c.app.name, c.task_source, c.source, c.start_directory])")
    assert_equal [41, 'api', 'explicit', 'frontmatter', File.join(@task_root, 'apps/api/subdir')], JSON.parse(provenance)
    before = domain_rows
    [['task_name', 'missing', /Task not found/], ['app', 'missing', /App.*not found|No app matches/i], ['dir', 'missing', /Directory does not exist/], ['dir', '../../../outside', /escapes|Directory does not exist/]].each do |key, value, error|
      bad = prompt_file({'task_name' => 'alpha', key => value})
      bytes = File.read(bad)
      failure('h', 'queue', 'pane-dir', bad, @git_root, error)
      assert_equal bytes, File.read(bad)
    end
    assert_equal before, domain_rows
    refute File.exist?(@marker)
  end

  def test_tracked_files_are_root_relative_at_root_and_app_mounts
    command('h', 'file', 'edit', 'api', cwd: File.join(@git_root, 'apps/api'))
    assert_equal({File.join(@git_root, 'apps/api/entry.rb') => "git-root file\n"}, marker.fetch('files'))
    command('h-app', 'file', '--app', 'api', 'edit', 'api', cwd: @task_root)
    assert_equal({File.join(@task_root, 'apps/api/entry.rb') => "task-root file\n"}, marker.fetch('files'))
    File.write(File.join(@sandbox, 'outside.txt'), 'secret')
    File.symlink(File.join(@sandbox, 'outside.txt'), File.join(@task_root, 'escape.txt'))
    ['../outside.txt', 'escape.txt'].each do |file|
      File.write(File.join(@config, 'app_files.yml'), {'api' => [file]}.to_yaml)
      File.write(@marker, 'unchanged')
      failure('h-app', 'file', '--app', 'api', 'edit', 'api', /escapes|outside.*root/i, cwd: @task_root)
      assert_equal 'unchanged', File.read(@marker)
    end
  end

  private

  def git(*args)
    stdout, stderr, status = Open3.capture3({'HOME' => @home, 'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1'}, '/usr/bin/git', *args)
    assert status.success?, "Fixture git failed: #{stdout}#{stderr}"
  end

  def ruby(*args, cwd: @outside, env: {})
    child_env = {'HOME' => @home, 'PATH' => "#{File.dirname(RbConfig.ruby)}:#{ROOT}/bin:#{ROOT}/exe:/usr/bin:/bin:/usr/sbin:/sbin", 'TZ' => 'UTC',
      'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'BUNDLE_PATH' => ENV['BUNDLE_PATH'],
      'RUBYLIB' => LIB, 'RUBYOPT' => "-rbundler/setup -r#{@preload}",
      'HIIRO_TEST_DB' => "sqlite://#{@db_path}", 'XDG_CONFIG_HOME' => File.join(@home, '.config'),
      'XDG_DATA_HOME' => File.join(@home, '.local/share'), 'CONTEXT_REPO' => ROOT, 'CONTEXT_MARKER' => @marker,
      'EDITOR' => @editor, 'SHELL' => '/bin/sh', 'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1'}
    Open3.capture3(child_env.merge(env), RbConfig.ruby, '-rbundler/setup', '-I', LIB, '-r', @preload, *args, chdir: cwd, unsetenv_others: true)
  end

  def script(code, **options)
    stdout, stderr, status = ruby('-e', code, **options)
    assert status.success?, "Ruby context failed: #{stdout}#{stderr}"
    stdout
  end

  def command(bin, *args, **options)
    path = File.join(ROOT, %w[h t tt].include?(bin) ? 'exe' : 'bin', bin)
    stdout, stderr, status = ruby(path, *args, **options)
    assert status.success?, "#{bin} #{args.inspect} failed (#{status.exitstatus}): #{stdout}#{stderr}"
    stdout
  end

  def failure(bin, *args, **options)
    expected = args.pop
    path = File.join(ROOT, %w[h t tt].include?(bin) ? 'exe' : 'bin', bin)
    stdout, stderr, status = ruby(path, *args, **options)
    assert_equal 1, status.exitstatus, "#{bin} #{args.inspect}: #{stdout}#{stderr}"
    assert_match expected, stdout + stderr
  end

  def context(expression, **options)
    code = "c = #{expression}; puts JSON.generate({task: c.task && [c.task.id, c.task.name], app: c.app&.name, project: c.project&.name, task_source: c.task_source, source: c.source, root: c.root_directory, directory: c.start_directory})"
    JSON.parse(script(code, **options))
  end

  def marker = JSON.parse(File.read(@marker))

  def domain_rows
    %i[tasks task_resources apps projects pins todos].to_h { |table| [table, @db[table].order(:id).all] }
  end

  def prompt_file(frontmatter)
    path = File.join(@sandbox, "prompt-#{Dir.glob(File.join(@sandbox, 'prompt-*.md')).length}.md")
    File.write(path, frontmatter.to_yaml + "---\nHarmless prompt.\n")
    path
  end
end
