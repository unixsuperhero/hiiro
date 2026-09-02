require "test_helper"
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

  def test_load_attaches_notify_method
    mock = MockHiiro.new

    Notify.load(mock)

    assert mock.respond_to?(:notify), "Expected hiiro to have notify method"
  end

  def test_load_registers_notify_subcommand
    mock = MockHiiro.new

    Notify.load(mock)

    assert mock.subcmds.key?(:notify), "Expected :notify subcommand to be registered"
  end

  def test_notify_method_builds_correct_args
    mock, herdr = build_notifier
    mock.notify("Hello", title: "Title")

    assert_equal [
      { title: "Title", body: "Hello", sound: :none },
    ], herdr.notifications
  end

  def test_notify_method_includes_link_when_provided
    mock, herdr = build_notifier
    mock.notify("Click me", link: "https://example.com")

    assert_equal "Click me\nhttps://example.com", herdr.notifications.first[:body]
  end

  def test_notify_method_includes_command_when_provided
    mock, herdr = build_notifier
    mock.notify("Run this", command: "open .")

    assert_equal "Run this\nopen .", herdr.notifications.first[:body]
  end

  private

  def build_notifier
    herdr = Struct.new(:notifications) do
      def notify(title, body:, sound:)
        notifications << { title:, body:, sound: }
      end
    end.new([])

    mock = MockHiiro.new
    mock.define_singleton_method(:herdr_client) { herdr }
    Notify.attach_methods(mock)
    [mock, herdr]
  end
end
