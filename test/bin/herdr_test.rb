require "test_helper"

class HerdrPluginTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-herdr")
  end

  def test_registers_expected_subcommands
    %i[install uninstall keys actions action popup].each do |subcmd|
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

  def test_manifest_actions_match_the_bin_and_open_the_popup_entrypoint
    manifest = File.read(File.expand_path("../../herdr-plugin/herdr-plugin.toml", __dir__))
    ids = manifest.scan(/^id = "([a-z-]+)"$/).flatten - ["hiiro", "popup"]
    out, = capture_io { @harness.run_subcmd(:actions) }
    assert_equal ids.sort, out.split.map { |line| line.delete_prefix("hiiro.") }.sort
    assert_includes manifest, 'command = ["h", "herdr", "popup"]'
  end
end
