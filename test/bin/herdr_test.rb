require "test_helper"

class HerdrPluginTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-herdr")
  end

  def test_registers_expected_subcommands
    %i[install uninstall keys actions action popup focus resize swap move layout arrange zoom].each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd}"
    end
  end

  def test_action_opens_the_plugin_popup_with_the_action_in_its_environment
    @harness.run_subcmd(:action, "switch")
    call = @harness.system_calls.last
    assert_match(/herdr\z/, call.first)
    assert_equal %w[plugin pane open --plugin hiiro --entrypoint popup --env HIIRO_HERDR_ACTION=switch --focus], call.drop(1)
  end

  def test_shell_and_nvim_actions_request_a_larger_popup
    @harness.run_subcmd(:action, "nvim")
    assert_includes @harness.system_calls.last, "--width"
    assert_includes @harness.system_calls.last, "HIIRO_HERDR_ACTION=nvim"
  end

  def test_unknown_action_is_rejected
    assert_raises(Hiiro::Error) { @harness.run_subcmd(:action, "bogus") }
    assert_empty @harness.system_calls
  end

  def test_pane_commands_accept_vim_directions
    @harness.run_subcmd(:focus, "h")
    @harness.run_subcmd(:resize, "j", "0.1")
    @harness.run_subcmd(:swap, "k")
    @harness.run_subcmd(:zoom)

    calls = @harness.system_calls.map { |call| [File.basename(call.first), *call.drop(1)] }
    assert_equal [
      ["herdr", "pane", "focus", "--current", "--direction", "left"],
      ["herdr", "pane", "resize", "--current", "--direction", "down", "--amount", "0.1"],
      ["herdr", "pane", "swap", "--current", "--direction", "up"],
      ["herdr", "pane", "zoom", "--current", "--toggle"],
    ], calls
  end

  def test_move_reflows_a_two_pane_tab_to_the_requested_edge
    current = Pane.new("w1:p2", "w1", "w1:t1")
    other = Pane.new("w1:p1", "w1", "w1:t1")
    herdr = MockHerdr.new(current, [other, current])
    harness = Hiiro::TestHarness.load_bin("bin/h-herdr") do
      define_singleton_method(:herdr_client) { herdr }
    end

    harness.run_subcmd(:move, "l", "0.5")
    calls = harness.system_calls.last(2).map { |call| [File.basename(call.first), *call.drop(1)] }
    assert_equal [
      ["herdr", "pane", "move", "w1:p2", "--new-tab", "--no-focus"],
      ["herdr", "pane", "move", "w1:p2", "--tab", "w1:t1",
        "--target-pane", "w1:p1", "--split", "right", "--ratio", "0.5", "--focus"],
    ], calls

    harness.run_subcmd(:move, "up", "0.25")
    calls = harness.system_calls.last(2).map { |call| [File.basename(call.first), *call.drop(1)] }
    assert_equal [
      ["herdr", "pane", "move", "w1:p1", "--new-tab", "--no-focus"],
      ["herdr", "pane", "move", "w1:p1", "--tab", "w1:t1",
        "--target-pane", "w1:p2", "--split", "down", "--ratio", "0.75", "--no-focus"],
    ], calls
  end

  def test_move_rejects_tabs_with_more_than_two_panes
    current = Pane.new("w1:p1", "w1", "w1:t1")
    panes = [current, Pane.new("w1:p2", "w1", "w1:t1"), Pane.new("w1:p3", "w1", "w1:t1")]
    herdr = MockHerdr.new(current, panes)
    harness = Hiiro::TestHarness.load_bin("bin/h-herdr") do
      define_singleton_method(:herdr_client) { herdr }
    end

    error = assert_raises(Hiiro::Error) { harness.run_subcmd(:move, "right") }
    assert_match(/exactly two panes/, error.message)
    assert_empty harness.system_calls
  end

  def test_keys_include_vim_layout_and_resize_bindings
    out, = capture_io { @harness.run_subcmd(:keys) }
    assert_includes out, 'key = "prefix+shift+l"'
    assert_includes out, 'command = "h herdr move right"'
    assert_includes out, 'key = "prefix+alt+h"'
    assert_includes out, 'command = "h herdr resize left"'
  end

  def test_manifest_actions_match_the_bin_and_open_the_popup_entrypoint
    manifest = File.read(File.expand_path("../../herdr-plugin/herdr-plugin.toml", __dir__))
    ids = manifest.scan(/^id = "([a-z-]+)"$/).flatten - ["hiiro", "popup"]
    out, = capture_io { @harness.run_subcmd(:actions) }
    assert_equal ids.sort, out.split.map { |line| line.delete_prefix("hiiro.") }.sort
    assert_includes manifest, 'command = ["h", "herdr", "popup"]'
  end

  Pane = Data.define(:id, :workspace_id, :tab_id)

  class MockHerdr
    def initialize(current, panes)
      @current = current
      @panes = panes
    end

    def current_pane = @current
    def panes(**) = @panes
  end
end
