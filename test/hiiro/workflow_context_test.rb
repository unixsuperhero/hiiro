require 'test_helper'
require 'rbconfig'

class WorkflowContextTest < Minitest::Test
  def context_for(root, directory = root)
    Hiiro::TaskLocation.for(nil, root: root, invocation_directory: root,
      terminal: Hiiro::Herdr::Location.new).with_directory(directory, source: :override)
  end

  def test_services_preserve_root_relative_env_and_saved_stop_directory
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      app = File.join(root, 'api')
      FileUtils.mkdir_p(app)
      config = File.join(root, 'explicit-services.yml')
      state = File.join(root, 'running.yml')
      File.write(config, YAML.dump('web' => {
        'base_dir' => 'api', 'env_file' => '.env',
        'env_vars' => { 'MODE' => { 'variations' => { 'local' => 'local', 'staging' => 'staging' } } },
        'start' => 'exec sleep 30', 'stop' => 'kill $PID; pwd > stopped', 'cleanup' => ['pwd > cleaned'],
      }, 'plain' => { 'env_file' => '.env.plain', 'env_vars' => {} }))
      manager = Hiiro::ServiceManager.new(config_file: config, state_file: state, context: context_for(root, app))
      manager.launcher = Hiiro::OwnedRun::Launcher.new(store: Hiiro::OwnedRun::Store.new(File.join(root, 'runs')))
      assert_equal app, manager.definition_for('web').base_directory
      assert_equal app, manager.definition_for('plain').base_directory
      manager.prepare_env('web')
      assert_equal "MODE=local\n", File.read(File.join(app, '.env'))
      script = manager.send(:write_env_prep_script, 'web@test', 'web', { 'MODE' => 'staging' })
      assert system(RbConfig.ruby, '-rbundler/setup', '-I', File.expand_path('../../lib', __dir__), script, chdir: app)
      assert_equal "MODE=staging\n", File.read(File.join(app, '.env'))
      refute File.exist?(File.join(app, 'api', '.env'))
      capture_io { assert manager.start('web', skip_env: true) }
      key = manager.instances.first.key
      assert_equal app, manager.instances.first.directory
      manager.context = context_for(root)
      capture_io { assert manager.stop(key) }
      assert_equal app, File.read(File.join(app, 'stopped')).strip
      assert_equal app, File.read(File.join(app, 'cleaned')).strip
      assert_equal({}, YAML.safe_load_file(state))
    end
  end

  def test_missing_or_ambiguous_service_never_writes_launch_artifacts
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      config = File.join(root, 'services.yml')
      state = File.join(root, 'running.yml')
      File.write(config, YAML.dump('web' => { 'base_dir' => 'missing', 'start' => 'false' },
        'websocket' => { 'start' => 'false' }, 'webgroup' => { 'services' => [{ 'name' => 'web' }] }))
      manager = Hiiro::ServiceManager.new(config_file: config, state_file: state, context: context_for(root))
      assert_equal 'web', manager.find_service('web')[:name]
      assert_nil manager.find_group('web')
      assert_raises(Hiiro::Error) { manager.find_service('we') }
      assert_raises(Hiiro::Error) { manager.find_group('we') }
      assert_raises(Hiiro::Error) { manager.start('') }
      assert_raises(Hiiro::Error) { manager.start('web') }
      refute File.exist?(state)
      refute Dir.exist?(File.join(root, 'scripts'))
      File.write(config, YAML.dump('web' => { 'start' => 'false' }))
      assert_equal 'web', manager.find_service('web')[:name]
      assert_raises(Hiiro::Error) { manager.start('') }
    end
  end

  def test_tracked_files_remain_root_relative_and_reject_realpath_escape
    Dir.mktmpdir do |sandbox|
      sandbox = File.realpath(sandbox)
      root = File.join(sandbox, 'root')
      app = File.join(root, 'api')
      outside = File.join(sandbox, 'outside')
      FileUtils.mkdir_p([app, outside])
      File.write(File.join(app, 'tracked'), 'root-relative')
      File.symlink(outside, File.join(root, 'escape'))
      File.symlink(File.join(sandbox, 'outside-missing'), File.join(root, 'dangling'))
      config = File.join(sandbox, 'files.yml')
      File.write(config, YAML.dump('api' => ['api/tracked'], 'bad' => ['escape/new/file'], 'dangling' => ['dangling']))
      files = Hiiro::AppFiles.new(config_file: config, context: context_for(root, app))
      assert_equal [File.join(app, 'tracked')], files.paths_for('api')
      assert_equal 'root-relative', File.read(files.paths_for('api').first)
      assert_raises(Hiiro::Error) { files.paths_for('bad') }
      assert_raises(Hiiro::Error) { files.paths_for('dangling') }
      refute File.exist?(File.join(sandbox, 'outside-missing'))
    end
  end

  def test_runner_discovers_supplied_repo_and_executes_from_effective_directory
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      repo = File.join(root, 'repo')
      app = File.join(repo, 'api')
      FileUtils.mkdir_p(app)
      assert system('git', 'init', '--quiet', '--initial-branch=main', repo)
      File.write(File.join(app, 'a file.rb'), 'one')
      File.write(File.join(app, "quote' space.rb"), 'quoted')
      File.write(File.join(repo, 'other.rb'), 'outside-app')
      config = File.join(root, 'tools.yml')
      File.write(config, YAML.dump('proof' => { 'file_extensions' => 'rb',
        'command' => "printf '%s\\n' [FILENAMES] > files.marker; pwd > cwd.marker" }))
      runner = Hiiro::RunnerTool.new(config_file: config, context: context_for(repo, app))
      assert_equal 'proof', runner.find_tool('proof')[:name]
      assert_raises(Hiiro::Error) { runner.find_tool('') }
      git = Hiiro::Git.new(nil, repo)
      assert_equal File.realpath(repo), git.root
      assert_equal ['a file.rb', "quote' space.rb"], runner.changed_files('dirty', git: git).sort
      assert runner.run(git: git)
      assert_equal app, File.read(File.join(app, 'cwd.marker')).strip
      assert_equal "a file.rb\nquote' space.rb\n", File.read(File.join(app, 'files.marker'))
    end
  end
end
