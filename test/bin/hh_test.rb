require "test_helper"

class HhTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/hh")
  end

  def test_registers_pane_control_subcommands
    %i[focus resize swap move layout arrange zoom].each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd}"
    end
  end

  def test_pane_controls_delegate_to_h_herdr
    @harness.run_subcmd(:move, "right", "0.5")
    @harness.run_subcmd(:resize, "h", "0.1")

    assert_equal [
      ["h", "herdr", "move", "right", "0.5"],
      ["h", "herdr", "resize", "h", "0.1"],
    ], @harness.system_calls
  end
end
