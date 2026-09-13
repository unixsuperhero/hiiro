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

class HiiroAddDefaultTest < Minitest::Test
  # Use Hiiro.new directly to avoid global_values leaking into Subcommand
  def make_hiiro(args_list, &block)
    hiiro = Hiiro.new("testbin-zzz", *args_list)
    hiiro.instance_eval(&block) if block
    hiiro
  end

  def test_using_default_true_when_no_subcommand_matches
    hiiro = make_hiiro(["foo", "bar"]) { add_subcmd(:greet) { :ok } }
    assert hiiro.runners.using_default?
  end

  def test_using_default_false_when_subcommand_matches
    hiiro = make_hiiro(["greet"]) { add_subcmd(:greet) { :ok } }
    refute hiiro.runners.using_default?
  end

  def test_using_default_false_with_prefix_match
    hiiro = make_hiiro(["gr"]) { add_subcmd(:greet) { :ok } }
    refute hiiro.runners.using_default?
  end

  def test_default_runner_receives_subcmd_prepended
    received = nil
    hiiro = make_hiiro(["foo", "bar"]) { add_default { |*a| received = a } }
    run_args = hiiro.runners.using_default? ? [hiiro.subcmd, *hiiro.args].compact : hiiro.args
    hiiro.runner.run(*run_args)
    assert_equal ["foo", "bar"], received
  end

  def test_default_runner_receives_subcmd_only_when_no_extra_args
    received = nil
    hiiro = make_hiiro(["foo"]) { add_default { |*a| received = a } }
    run_args = hiiro.runners.using_default? ? [hiiro.subcmd, *hiiro.args].compact : hiiro.args
    hiiro.runner.run(*run_args)
    assert_equal ["foo"], received
  end

  def test_normal_subcmd_runner_does_not_receive_subcmd_prepended
    received = nil
    hiiro = make_hiiro(["greet", "world"]) { add_subcmd(:greet) { |*a| received = a } }
    run_args = hiiro.runners.using_default? ? [hiiro.subcmd, *hiiro.args].compact : hiiro.args
    hiiro.runner.run(*run_args)
    assert_equal ["world"], received
  end
end

class HiiroAddCmdTest < Minitest::Test
  def test_auto_flags_and_explicit_task_option_reach_handler
    hiiro = Hiiro.new("testbin-zzz")
    hiiro.add_option(:task, short: :t)
    hiiro.add_cmd(:example, opts: %i[a b c d task]) do
      [opts.to_h, opts.args]
    end

    result = hiiro.run_subcommand(:example, "--a", "first", "-b", "second", "--task", "feature")

    assert_equal [
      { help: false, a: true, b: true, c: false, d: false, task: "feature" },
      %w[first second]
    ], result
  end

  def test_help_lists_only_selected_options_without_running_handler
    hiiro = Hiiro.new("testbin-zzz")
    hiiro.add_option(:task, short: :t)
    hiiro.add_flag(:unselected)
    calls = []
    hiiro.add_cmd(:example, opts: %i[a history task]) { calls << opts.args }

    hiiro.run_subcommand(:example, "payload")
    assert_equal [["payload"]], calls
    calls.clear

    %w[-h --help].each do |help|
      output, = capture_io { hiiro.run_subcommand(:example, help) }

      assert_empty calls
      assert_match(/-a, --a/, output)
      refute_match(/--a[^\n]*<value>/, output)
      assert_match(/--history/, output)
      assert_match(/-t, --task[^\n]*<value>/, output)
      assert_match(/-h, --help/, output)
      refute_match(/--unselected/, output)
    end
  end

  def test_nested_add_cmd_preserves_leaf_options_and_help
    calls = []
    dispatch = lambda do |*arguments|
      parent = Hiiro.new("testbin-zzz", "group", "leaf", *arguments, external_commands: false)
      parent.add_cmd(:group, passthrough: true) do
        child = make_child(:group, args, external_commands: false) do
          add_option :task, short: :t
          add_cmd(:leaf, opts: %i[task all]) do
            calls << { task: opts.task, all: opts.all, args: opts.args }
          end
        end
        child.runner.run(*child.args)
      end
      parent.runner.run(*parent.args)
    end

    dispatch.call("-t", "demo", "--all", "payload")
    assert_equal [{ task: "demo", all: true, args: ["payload"] }], calls

    output, = capture_io { dispatch.call("--help") }
    assert_equal [{ task: "demo", all: true, args: ["payload"] }], calls
    assert_match(/-t, --task/, output)
    assert_match(/--all/, output)
  end

  def test_generated_help_uses_command_declarations_not_wrapper_metadata
    hiiro = Hiiro.new("testbin-zzz", external_commands: false)
    hiiro.add_cmd(:list) { puts "listed" }
    hiiro.add_cmd(:show, args: %i[payload]) { puts "shown" }

    output, = capture_io { assert_raises(SystemExit) { hiiro.help } }
    assert_match(/show\s+<payload>/, output)
    assert_match(/hiiro_test\.rb:/, output)
    refute_match(/\[\*raw_args\]/, output)
  end
end

class HiiroRunnersBinTest < Minitest::Test
  def test_disabling_external_commands_keeps_task_dispatch_inside_the_cli
    previous_path = ENV["PATH"]
    Dir.mktmpdir do |dir|
      external = File.join(dir, "testbin-zzz-example")
      File.write(external, "#!/bin/sh\nprintf 'external\\n'\n")
      File.chmod(0o755, external)
      ENV["PATH"] = dir

      default = Hiiro.new("testbin-zzz", "example")
      default.add_cmd(:example) { puts "internal" }
      output, = capture_subprocess_io { default.runner.run }
      assert_equal "external\n", output

      isolated = Hiiro.new("testbin-zzz", "example", external_commands: false)
      isolated.add_cmd(:example) { puts "internal" }
      output, = capture_io { isolated.runner.run }
      assert_equal "internal\n", output
    end
  ensure
    ENV["PATH"] = previous_path
  end

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
