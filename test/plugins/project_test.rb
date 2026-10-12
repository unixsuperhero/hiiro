require 'test_helper'
require_relative '../../plugins/project'

class ProjectPluginTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::Project.dataset.delete
  end

  def teardown
    Hiiro::Project.dataset.delete
  end

  def test_project_dirs_only_include_directories
    mock = MockHiiro.new
    Project.load(mock)
    with_temp_dir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'proj', 'alpha'))
      File.write(File.join(dir, 'proj', 'not-a-project'), 'ordinary file')
      Dir.stub(:home, dir) do
        assert_equal({'alpha' => File.join(dir, 'proj', 'alpha')}, mock.project_dirs)
      end
    end
  end

  def test_plugin_and_manager_ignore_recovery_yaml_and_preserve_its_bytes
    mock = MockHiiro.new
    Project.load(mock)
    with_temp_dir do |dir|
      config_dir = File.join(dir, '.config', 'hiiro')
      FileUtils.mkdir_p(config_dir)
      file = File.join(config_dir, 'projects.yml')
      recovery = "legacy: /recovery/path\n"
      File.write(file, recovery)
      Dir.stub(:home, dir) do
        assert_equal({}, mock.projects_from_config)
        manager = Hiiro::Projects.new
        manager.save_project('canonical', '/canonical/path')
        record = Hiiro::Project.find_by_name('canonical')
        manager.save_project('canonical', '/updated/path')
        assert_equal({'canonical' => '/updated/path'}, mock.projects_from_config)
        assert_equal '/updated/path', manager.find('canonical')
        assert_equal record.id, Hiiro::Project.find_by_name('canonical').id
        assert_equal recovery, File.read(file)
      end
    end
  end

  def test_database_read_failure_does_not_restore_recovery_aliases
    manager = Hiiro::Projects.new
    Hiiro::Project.stub(:all_as_hash, -> { raise Sequel::DatabaseError, 'unavailable' }) do
      assert_raises(Sequel::DatabaseError) { manager.from_config }
    end
    manager.save_project('canonical', '/canonical/path')
    assert_equal({'canonical' => '/canonical/path'}, manager.from_config)
  end
end
