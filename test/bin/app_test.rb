require 'test_helper'

class AppTest < Minitest::Test
  def setup
    Hiiro::AppRecord.dataset.delete
    @harness = Hiiro::TestHarness.load_bin('bin/h-app') do
      define_singleton_method(:environment) { Hiiro::Environment.new }
    end
  end

  def teardown
    Hiiro::AppRecord.dataset.delete
  end

  def test_add_list_and_remove_share_canonical_aliases
    capture_io { @harness.run_subcmd(:add, 'frontend', 'apps/frontend') }
    frontend = Hiiro::AppRecord.find_by_name('frontend')
    output, = capture_io { @harness.run_subcmd(:ls) }
    assert_includes output, 'frontend'
    assert_includes output, 'apps/frontend'
    capture_io { @harness.run_subcmd(:add, 'api', 'services/api') }
    api = Hiiro::AppRecord.find_by_name('api')
    capture_io { @harness.run_subcmd(:remove, 'frontend') }
    assert_nil Hiiro::AppRecord[frontend.id]
    assert_equal [[api.id, 'api', 'services/api']], Hiiro::AppRecord.all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_show_is_a_stable_id_database_projection
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    output, = capture_io { @harness.run_subcmd(:show) }
    assert_equal [{'id' => app.id, 'name' => 'frontend', 'path' => 'apps/frontend'}], YAML.safe_load(output)
  end

  def test_edit_changes_selected_fields_without_replacing_aliases
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    other = Hiiro::AppRecord.create(name: 'api', path: 'services/api')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      Hiiro::AppRecord[app.id].update(name: 'concurrent-name')
      Hiiro::AppRecord.create(name: 'worker', path: 'services/worker')
      rows.first['path'] = 'apps/new-frontend'
      File.write(path, [rows.first].to_yaml)
      true
    end
    capture_io { @harness.run_subcmd(:config) }
    assert_equal ['concurrent-name', 'apps/new-frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
    assert_equal ['api', 'services/api'], Hiiro::AppRecord[other.id].values.values_at(:name, :path)
    assert_equal 'services/worker', Hiiro::AppRecord.find_by_name('worker').path
  end

  def test_forged_id_and_invalid_rows_cannot_partially_write
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 'changed'
      rows << {'id' => app.id + 1000, 'name' => 'forged', 'path' => 'forged'}
      File.write(path, rows.to_yaml)
      true
    end
    _, error = capture_io { @harness.run_subcmd(:edit) }
    assert_includes error, 'Unknown or duplicate alias ID'
    assert_equal [[app.id, 'frontend', 'apps/frontend']], Hiiro::AppRecord.all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_semantically_invalid_edit_preserves_existing_aliases
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 42
      File.write(path, rows.to_yaml)
      true
    end
    _, error = capture_io { @harness.run_subcmd(:edit) }
    assert_includes error, 'path must be a nonempty string'
    assert_equal ['frontend', 'apps/frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
  end

  def test_failed_editor_does_not_commit_valid_yaml
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 'changed'
      File.write(path, rows.to_yaml)
      false
    end
    capture_io { @harness.run_subcmd(:edit) }
    assert_equal ['frontend', 'apps/frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
  end

  def test_paths_share_exact_app_selection_and_invocation_relative_output
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      FileUtils.mkdir_p(File.join(root, 'apps', 'api'))
      FileUtils.mkdir_p(File.join(root, 'nested'))
      Hiiro::AppRecord.create(name: 'apiary', path: 'apps/apiary')
      Hiiro::AppRecord.create(name: 'api', path: 'apps/api')
      selected = Hiiro::TaskLocation.for(nil, root: root, invocation_directory: File.join(root, 'nested'))
      @harness.stub_method(:context) { selected }
      relative, = capture_io { @harness.run_subcmd(:path, 'api') }
      absolute, = capture_io { @harness.run_subcmd(:abspath, 'api') }
      assert_equal "../apps/api\n", relative
      assert_equal "#{root}/apps/api\n", absolute
      root_output, = capture_io { @harness.run_subcmd(:path) }
      assert_equal "..\n", root_output
    end
  end

  def test_missing_and_ambiguous_apps_fail_instead_of_using_another_directory
    Dir.mktmpdir do |root|
      selected = Hiiro::TaskLocation.for(nil, root: root)
      @harness.stub_method(:context) { selected }
      Hiiro::AppRecord.create(name: 'alpha', path: 'alpha')
      Hiiro::AppRecord.create(name: 'alpine', path: 'alpine')
      $stdin.stub(:tty?, false) do
        assert_raises(Hiiro::Error) { @harness.run_subcmd(:abspath, 'al') }
        assert_raises(Hiiro::Error) { @harness.run_subcmd(:abspath, 'unknown') }
        assert_raises(Hiiro::Error) { @harness.run_subcmd(:abspath, 'alpha') }
      end
    end
  end

  def test_blank_app_and_project_selectors_cannot_launch_native_commands
    require 'open3'
    Dir.mktmpdir do |directory|
      sandbox = File.realpath(directory)
      home = File.join(sandbox, 'home')
      root = File.join(sandbox, 'code')
      api = File.join(root, 'api')
      FileUtils.mkdir_p([File.join(home, 'proj'), api])
      repo = File.expand_path('../..', __dir__)
      environment = {'HOME' => home, 'HIIRO_TEST_DB' => "sqlite://#{sandbox}/proof.db",
                     'HERDR_WORKSPACE_ID' => nil, 'HERDR_TAB_ID' => nil, 'HERDR_PANE_ID' => nil}
      ruby = [RbConfig.ruby, '-rbundler/setup', '-I', File.join(repo, 'lib')]
      seed = "require 'hiiro'; Hiiro::DB.setup!; Hiiro::AppRecord.create(name: 'api', path: 'api'); Hiiro::Table.named('project').add('alpha', value: #{api.inspect})"
      output, error, status = Open3.capture3(environment, *ruby, '-e', seed, chdir: root)
      assert status.success?, "#{output} #{error}"
      payload = 'File.write(ARGV.shift, JSON.generate(ARGV))'
      {'h-app' => 'api', 'h-project' => 'alpha'}.each do |bin, valid_name|
        ['', '  '].each_with_index do |blank, index|
          marker = File.join(sandbox, "#{bin}-invalid-#{index}")
          output, error, status = Open3.capture3(environment, *ruby, File.join(repo, 'bin', bin), 'sh', blank,
                                               RbConfig.ruby, '-rjson', '-e', payload, marker, chdir: root)
          assert_equal 1, status.exitstatus, "#{output} #{error}"
          refute File.exist?(marker), "#{bin} launched with a blank selector"
        end
        marker = File.join(sandbox, "#{bin}-valid")
        output, error, status = Open3.capture3(environment, *ruby, File.join(repo, 'bin', bin), 'sh', valid_name,
                                             RbConfig.ruby, '-rjson', '-e', payload, marker, '', chdir: root)
        assert status.success?, "#{output} #{error}"
        assert_equal [''], JSON.parse(File.read(marker))
      end
    end
  end
end
