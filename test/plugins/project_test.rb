require "test_helper"
# require_relative "../../plugins/tmux"
require_relative "../../plugins/project"

class ProjectPluginTest < Minitest::Test
  def test_project_module_responds_to_load
    assert_respond_to Project, :load
  end

  def test_project_module_responds_to_add_subcommands
    assert_respond_to Project, :add_subcommands
  end

  def test_project_module_responds_to_attach_methods
    assert_respond_to Project, :attach_methods
  end
end
