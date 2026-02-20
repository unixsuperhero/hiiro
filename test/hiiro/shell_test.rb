require "test_helper"
require "hiiro/shell"

class ShellTest < Minitest::Test
  include TestHelpers

  def test_pipe_returns_chomped_output_on_success
    result = Hiiro::Shell.pipe("hello world", "cat")

    assert_equal "hello world", result
  end

  def test_pipe_returns_nil_on_failure
    result = Hiiro::Shell.pipe("test", "false")

    assert_nil result
  end

  def test_pipe_with_array_command
    result = Hiiro::Shell.pipe("hello", "head", "-c", "3")

    assert_equal "hel", result
  end

  def test_pipe_lines_with_array_input
    result = Hiiro::Shell.pipe_lines(["line1", "line2", "line3"], "cat")

    assert_equal "line1\nline2\nline3", result
  end

  def test_pipe_lines_with_string_input
    result = Hiiro::Shell.pipe_lines("single line", "cat")

    assert_equal "single line", result
  end

  def test_pipe_lines_joins_array_with_newlines
    result = Hiiro::Shell.pipe_lines(["a", "b", "c"], "cat")

    assert_equal "a\nb\nc", result
  end

  def test_pipe_handles_empty_input
    result = Hiiro::Shell.pipe("", "cat")

    assert_equal "", result
  end

  def test_pipe_handles_multiline_input
    input = "line1\nline2\nline3"
    result = Hiiro::Shell.pipe(input, "cat")

    assert_equal input, result
  end
end
