require "test_helper"

class OptionsTest < Minitest::Test
  def test_flag_default_false
    opts = Hiiro::Options.new([]) do
      flag :verbose
    end

    refute opts.verbose
    refute opts.verbose?
  end

  def test_flag_presence_sets_true
    opts = Hiiro::Options.new(["--verbose"]) do
      flag :verbose
    end

    assert opts.verbose
    assert opts.verbose?
  end

  def test_flag_with_short_option
    opts = Hiiro::Options.new(["-v"]) do
      flag :verbose, short: "v"
    end

    assert opts.verbose
  end

  def test_flag_default_true_inverted_by_presence
    opts = Hiiro::Options.new(["--no-color"]) do
      flag :no_color, default: true
    end

    refute opts.no_color
  end

  def test_option_with_value
    opts = Hiiro::Options.new(["--name", "alice"]) do
      option :name
    end

    assert_equal "alice", opts.name
  end

  def test_option_with_equals_syntax
    opts = Hiiro::Options.new(["--name=alice"]) do
      option :name
    end

    assert_equal "alice", opts.name
  end

  def test_option_with_short
    opts = Hiiro::Options.new(["-n", "alice"]) do
      option :name, short: "n"
    end

    assert_equal "alice", opts.name
  end

  def test_option_with_default
    opts = Hiiro::Options.new([]) do
      option :count, default: 10
    end

    assert_equal 10, opts.count
  end

  def test_option_integer_coercion
    opts = Hiiro::Options.new(["--count", "42"]) do
      option :count, type: :integer
    end

    assert_equal 42, opts.count
  end

  def test_option_float_coercion
    opts = Hiiro::Options.new(["--rate", "3.14"]) do
      option :rate, type: :float
    end

    assert_in_delta 3.14, opts.rate, 0.001
  end

  def test_multi_option
    opts = Hiiro::Options.new(["--tag", "ruby", "--tag", "cli"]) do
      option :tag, multi: true
    end

    assert_equal %w[ruby cli], opts.tag
  end

  def test_remaining_args
    opts = Hiiro::Options.new(["--verbose", "file1.txt", "file2.txt"]) do
      flag :verbose
    end

    assert_equal %w[file1.txt file2.txt], opts.remaining_args
    assert_equal opts.remaining_args, opts.args
  end

  def test_double_dash_separator
    opts = Hiiro::Options.new(["--verbose", "--", "--not-a-flag"]) do
      flag :verbose
    end

    assert opts.verbose
    assert_equal ["--not-a-flag"], opts.remaining_args
  end

  def test_combined_short_flags
    opts = Hiiro::Options.new(["-abc"]) do
      flag :a, short: "a"
      flag :b, short: "b"
      flag :c, short: "c"
    end

    assert opts.a
    assert opts.b
    assert opts.c
  end

  def test_short_option_with_attached_value
    opts = Hiiro::Options.new(["-nfoo"]) do
      option :name, short: "n"
    end

    assert_equal "foo", opts.name
  end

  def test_to_h
    opts = Hiiro::Options.new(["--verbose", "--name", "test"]) do
      flag :verbose
      option :name
    end

    hash = opts.to_h
    assert_equal true, hash[:verbose]
    assert_equal "test", hash[:name]
  end

  def test_bracket_access
    opts = Hiiro::Options.new(["--name", "test"]) do
      option :name
    end

    assert_equal "test", opts[:name]
  end

  def test_respond_to_missing
    opts = Hiiro::Options.new([]) do
      flag :verbose
    end

    assert_respond_to opts, :verbose
    assert_respond_to opts, :verbose?
    refute_respond_to opts, :unknown
  end

  def test_hyphenated_option_name
    opts = Hiiro::Options.new(["--dry-run"]) do
      flag :dry_run
    end

    assert opts.dry_run
  end
end

class OptionsDefinitionTest < Minitest::Test
  def test_definition_flag
    defn = Hiiro::Options::Definition.new(:verbose, type: :flag)

    assert defn.flag?
    assert_equal "--verbose", defn.long_form
    assert_nil defn.short_form
  end

  def test_definition_with_short
    defn = Hiiro::Options::Definition.new(:verbose, short: "v", type: :flag)

    assert_equal "-v", defn.short_form
  end

  def test_definition_match
    defn = Hiiro::Options::Definition.new(:verbose, short: "v", type: :flag)

    assert defn.match?("--verbose")
    assert defn.match?("-v")
    refute defn.match?("--quiet")
  end

  def test_definition_coerce_integer
    defn = Hiiro::Options::Definition.new(:count, type: :integer)

    assert_equal 42, defn.coerce("42")
  end

  def test_definition_coerce_float
    defn = Hiiro::Options::Definition.new(:rate, type: :float)

    assert_in_delta 3.14, defn.coerce("3.14"), 0.001
  end

  def test_definition_coerce_string
    defn = Hiiro::Options::Definition.new(:name, type: :string)

    assert_equal "test", defn.coerce("test")
  end
end
