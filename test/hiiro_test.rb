require "test_helper"

class HiiroTest < Minitest::Test
  include TestHelpers

  def test_version_is_defined
    refute_nil Hiiro::VERSION
  end

  def test_string_underscore_basic
    assert_equal "foo_bar", "FooBar".underscore
    assert_equal "foo_bar_baz", "FooBarBaz".underscore
  end

  def test_string_underscore_with_namespace
    assert_equal "foo/bar_baz", "Foo::BarBaz".underscore
  end

  def test_string_underscore_already_underscored
    assert_equal "foo_bar", "foo_bar".underscore
  end

  def test_string_underscore_with_acronyms
    assert_equal "html_parser", "HTMLParser".underscore
    assert_equal "api_request", "APIRequest".underscore
  end

  def test_args_flags_parsing
    args = Hiiro::Args.new("-abc", "value")
    assert_equal ["a", "b", "c"], args.flags
    assert args.flag?("a")
    assert args.flag?("b")
    refute args.flag?("d")
  end

  def test_args_values
    args = Hiiro::Args.new("-f", "value1", "value2")
    assert_equal ["value1", "value2"], args.values
  end

  def test_args_flag_value
    args = Hiiro::Args.new("-f", "test.txt", "other")
    assert_equal "test.txt", args.flag_value("f")
  end

  def test_args_combined_flags
    args = Hiiro::Args.new("-abc", "-d", "val")
    assert args.flag?("a")
    assert args.flag?("b")
    assert args.flag?("c")
    assert args.flag?("d")
    assert_equal "val", args.flag_value("d")
  end

  def test_config_config_dir
    config_path = Hiiro::Config.config_dir
    assert config_path.include?(".config/hiiro")
  end

  def test_config_plugin_dir
    plugin_path = Hiiro::Config.plugin_dir
    assert plugin_path.include?("plugins")
  end
end

class HiiroRunnersSubcommandTest < Minitest::Test
  def test_subcommand_exact_match
    handler = -> { :ok }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert subcommand.exact_match?("test")
    refute subcommand.exact_match?("tes")
    refute subcommand.exact_match?("testing")
  end

  def test_subcommand_prefix_match
    handler = -> { :ok }
    subcommand = Hiiro::Runners::Subcommand.new("h", "testing", handler)

    assert subcommand.match?("test")
    assert subcommand.match?("testing")
    refute subcommand.match?("xyz")
  end

  def test_subcommand_full_name
    handler = -> { :ok }
    subcommand = Hiiro::Runners::Subcommand.new("mybin", "mysubcmd", handler)

    assert_equal "mybin-mysubcmd", subcommand.full_name
  end

  def test_subcommand_type
    handler = -> { :ok }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert_equal :subcommand, subcommand.type
  end

  def test_subcommand_params_string_with_required
    handler = ->(name) { name }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert_equal "<name>", subcommand.params_string
  end

  def test_subcommand_params_string_with_optional
    handler = ->(name = nil) { name }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert_equal "[name]", subcommand.params_string
  end

  def test_subcommand_params_string_with_rest
    handler = ->(*args) { args }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert_nil subcommand.params_string
  end

  def test_subcommand_params_string_with_keyword
    handler = ->(name:) { name }
    subcommand = Hiiro::Runners::Subcommand.new("h", "test", handler)

    assert_equal "<name:>", subcommand.params_string
  end
end

class HiiroRunnersBinTest < Minitest::Test
  def test_bin_subcommand_name
    bin = Hiiro::Runners::Bin.new("h", "/usr/local/bin/h-project")

    assert_equal "project", bin.subcommand_name
  end

  def test_bin_exact_match
    bin = Hiiro::Runners::Bin.new("h", "/usr/local/bin/h-project")

    assert bin.exact_match?("project")
    refute bin.exact_match?("proj")
  end

  def test_bin_prefix_match
    bin = Hiiro::Runners::Bin.new("h", "/usr/local/bin/h-project")

    assert bin.match?("proj")
    assert bin.match?("project")
    refute bin.match?("xyz")
  end

  def test_bin_type
    bin = Hiiro::Runners::Bin.new("h", "/usr/local/bin/h-project")

    assert_equal :bin, bin.type
  end

  def test_bin_location
    bin = Hiiro::Runners::Bin.new("h", "/usr/local/bin/h-project")

    assert_equal "/usr/local/bin/h-project", bin.location
  end
end
