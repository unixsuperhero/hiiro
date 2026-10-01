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

  def test_read_input_reads_a_file
    with_input_files("one\n") do |path|
      assert_equal "one\n", Hiiro::Shell.read_input(path)
    end
  end

  def test_read_input_concatenates_files
    with_input_files("one\n", "two\n") do |first, second|
      assert_equal "one\ntwo\n", Hiiro::Shell.read_input(first, second)
    end
  end

  def test_read_input_ignores_args_that_are_not_files
    with_input_files("one\n") do |path|
      assert_equal "one\n", Hiiro::Shell.read_input("--flag", path, "missing.txt", Dir.tmpdir)
    end
  end

  def test_read_input_reads_piped_stdin_without_args
    assert_equal "piped", read_input_in_subprocess("piped")
  end

  def test_read_input_reads_piped_stdin_for_dash
    assert_equal "piped", read_input_in_subprocess("piped", "-")
  end

  def test_read_input_places_stdin_at_dash_between_files
    with_input_files("one\n", "two\n") do |first, second|
      assert_equal "one\npiped\ntwo", read_input_in_subprocess("piped\n", first, "-", second)
    end
  end

  def test_read_input_prefers_files_over_piped_stdin
    with_input_files("one\n") do |path|
      assert_equal "one", read_input_in_subprocess("piped", path)
    end
  end

  def test_read_input_aborts_at_a_terminal_without_input
    $stdin.stub(:tty?, true) do
      _out, err = capture_io do
        assert_raises(SystemExit) { Hiiro::Shell.read_input("missing.txt") }
      end

      assert_match(/no input/, err)
    end
  end

  private

  def with_input_files(*contents)
    files = contents.map do |content|
      Tempfile.new("read-input").tap { |file| file.write(content); file.close }
    end
    yield(*files.map(&:path))
  ensure
    files&.each(&:unlink)
  end

  def read_input_in_subprocess(stdin_data, *args)
    lib = File.expand_path("../../lib", __dir__)
    script = "print Hiiro::Shell.read_input(*ARGV)"

    Hiiro::Shell.pipe(stdin_data, "ruby", "-I", lib, "-r", "hiiro/shell", "-e", script, *args)
  end
end
