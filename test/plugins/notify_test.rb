require "test_helper"
require_relative "../../plugins/tmux"
require_relative "../../plugins/notify"

class NotifyPluginTest < Minitest::Test
  def test_notify_module_responds_to_load
    assert_respond_to Notify, :load
  end

  def test_notify_module_responds_to_add_subcommands
    assert_respond_to Notify, :add_subcommands
  end

  def test_notify_module_responds_to_attach_methods
    assert_respond_to Notify, :attach_methods
  end
end
