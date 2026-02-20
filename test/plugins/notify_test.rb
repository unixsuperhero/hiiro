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
    mock = MockHiiro.new
    captured_args = nil

    # Stub system to capture the args
    mock.define_singleton_method(:system) do |*args|
      captured_args = args
      true
    end

    Notify.attach_methods(mock)
    mock.notify("Hello", title: "Title")

    # Should include message and title flags
    assert_includes captured_args, '-message'
    assert_includes captured_args, 'Hello'
    assert_includes captured_args, '-title'
    assert_includes captured_args, 'Title'
  end

  def test_notify_method_includes_link_when_provided
    mock = MockHiiro.new
    captured_args = nil

    mock.define_singleton_method(:system) do |*args|
      captured_args = args
      true
    end

    Notify.attach_methods(mock)
    mock.notify("Click me", link: "https://example.com")

    assert_includes captured_args, '-open'
    assert_includes captured_args, 'https://example.com'
  end

  def test_notify_method_includes_command_when_provided
    mock = MockHiiro.new
    captured_args = nil

    mock.define_singleton_method(:system) do |*args|
      captured_args = args
      true
    end

    Notify.attach_methods(mock)
    mock.notify("Run this", command: "open .")

    assert_includes captured_args, '-execute'
    assert_includes captured_args, 'open .'
  end
end
