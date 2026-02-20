require "test_helper"
require_relative "../../plugins/project"

class ProjectPluginTest < Minitest::Test
  include TestHelpers

  def test_project_module_responds_to_load
    assert_respond_to Project, :load
  end

  def test_project_module_responds_to_add_subcommands
    assert_respond_to Project, :add_subcommands
  end

  def test_project_module_responds_to_attach_methods
    assert_respond_to Project, :attach_methods
  end

  def test_load_attaches_project_dirs_method
    mock = MockHiiro.new

    Project.load(mock)

    assert mock.respond_to?(:project_dirs), "Expected hiiro to have project_dirs method"
  end

  def test_load_attaches_projects_from_config_method
    mock = MockHiiro.new

    Project.load(mock)

    assert mock.respond_to?(:projects_from_config), "Expected hiiro to have projects_from_config method"
  end

  def test_load_registers_project_subcommand
    mock = MockHiiro.new

    Project.load(mock)

    assert mock.subcmds.key?(:project), "Expected :project subcommand to be registered"
  end

  def test_project_dirs_returns_hash
    mock = MockHiiro.new

    Project.attach_methods(mock)

    with_temp_dir do |dir|
      # Create mock proj directory with projects
      proj_dir = File.join(dir, 'proj')
      FileUtils.mkdir_p(File.join(proj_dir, 'project1'))
      FileUtils.mkdir_p(File.join(proj_dir, 'project2'))

      Dir.stub(:home, dir) do
        dirs = mock.project_dirs

        assert_kind_of Hash, dirs
        assert dirs.key?('project1')
        assert dirs.key?('project2')
      end
    end
  end

  def test_projects_from_config_returns_empty_hash_when_no_file
    mock = MockHiiro.new

    Project.attach_methods(mock)

    with_temp_dir do |dir|
      Dir.stub(:home, dir) do
        projects = mock.projects_from_config

        assert_equal({}, projects)
      end
    end
  end

  def test_projects_from_config_loads_yaml_file
    mock = MockHiiro.new

    Project.attach_methods(mock)

    with_temp_dir do |dir|
      config_dir = File.join(dir, '.config', 'hiiro')
      FileUtils.mkdir_p(config_dir)

      projects_file = File.join(config_dir, 'projects.yml')
      File.write(projects_file, YAML.dump({
        'myproject' => '/path/to/myproject',
        'another' => '/path/to/another'
      }))

      Dir.stub(:home, dir) do
        projects = mock.projects_from_config

        assert_equal '/path/to/myproject', projects['myproject']
        assert_equal '/path/to/another', projects['another']
      end
    end
  end
end
