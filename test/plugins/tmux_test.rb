require "test_helper"
require_relative "../../plugins/tmux"

class TmuxPluginTest < Minitest::Test
  def test_tmux_module_responds_to_load
    assert_respond_to Tmux, :load
  end

  def test_tmux_module_responds_to_attach_methods
    assert_respond_to Tmux, :attach_methods
  end
end
