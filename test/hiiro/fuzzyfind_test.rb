require "test_helper"
require "hiiro/fuzzyfind"

class FuzzyfindTest < Minitest::Test
  include TestHelpers

  def test_tools_constant_includes_sk_and_fzf
    assert_includes Hiiro::Fuzzyfind::TOOLS, 'sk'
    assert_includes Hiiro::Fuzzyfind::TOOLS, 'fzf'
  end

  def test_tool_returns_first_available_tool
    # This tests the actual system - returns nil if neither available
    result = Hiiro::Fuzzyfind.tool
    if result
      assert_includes Hiiro::Fuzzyfind::TOOLS, result
    else
      assert_nil result
    end
  end

  def test_select_calls_shell_pipe_lines
    # Stub Shell.pipe_lines to verify it's called correctly
    lines = ["option1", "option2", "option3"]
    captured_lines = nil
    captured_tool = nil

    Hiiro::Shell.stub(:pipe_lines, ->(l, t) { captured_lines = l; captured_tool = t; "option2" }) do
      Hiiro::Fuzzyfind.stub(:tool!, "sk") do
        result = Hiiro::Fuzzyfind.select(lines)

        assert_equal ["option1", "option2", "option3"], captured_lines
        assert_equal "sk", captured_tool
        assert_equal "option2", result
      end
    end
  end

  def test_map_select_returns_value_for_selected_key
    mapping = {
      "Display One" => "value1",
      "Display Two" => "value2",
      "Display Three" => "value3"
    }

    Hiiro::Fuzzyfind.stub(:select, "Display Two") do
      result = Hiiro::Fuzzyfind.map_select(mapping)
      assert_equal "value2", result
    end
  end

  def test_map_select_returns_nil_for_unknown_key
    mapping = { "Known" => "known_value" }

    Hiiro::Fuzzyfind.stub(:select, "Unknown") do
      result = Hiiro::Fuzzyfind.map_select(mapping)
      assert_nil result
    end
  end

  def test_map_select_handles_nil_selection
    mapping = { "Option" => "value" }

    Hiiro::Fuzzyfind.stub(:select, nil) do
      result = Hiiro::Fuzzyfind.map_select(mapping)
      assert_nil result
    end
  end
end
