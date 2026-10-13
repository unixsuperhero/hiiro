require_relative "../test_helper"

class CatalogTest < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir("hiiro-catalog-"))
    @first = dir("first")
    @second = dir("second")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_only_executable_files_and_valid_links_are_candidates
    exe(@first, "zz-run")
    File.write(File.join(@first, "zz-plain"), "#!/bin/sh\n")
    FileUtils.mkdir(File.join(@first, "zz-folder"))
    File.chmod(0o755, File.join(@first, "zz-folder"))
    File.symlink(File.join(@first, "missing"), File.join(@first, "zz-broken"))
    File.symlink(File.join(@first, "zz-run"), File.join(@first, "zz-linked"))

    catalog = Hiiro::Catalog.new("zz", path: @first)

    assert_equal [%w[linked external], %w[run external]], catalog.entries.map { |e| [e.name, e.kind.to_s] }
    assert_equal :none, catalog.resolve("plain").status
    assert_equal :none, catalog.resolve("folder").status
    assert_equal :none, catalog.resolve("broken").status
  end

  def test_first_path_entry_wins_and_later_copies_are_shadowed_not_ambiguous
    winner = exe(@first, "zz-tool")
    loser = exe(@second, "zz-tool")

    catalog = Hiiro::Catalog.new("zz", path: [@first, @second, @first].join(":"))
    entry = catalog.resolve("to").entry

    assert_equal :prefix, catalog.resolve("to").status
    assert_equal winner, entry.source
    assert_equal [{ name: "tool", kind: "external", source: loser }], entry.shadowed.map(&:to_h)
    assert_equal loser, Hiiro::Catalog.new("zz", path: [@second, @first].join(":")).resolve("tool").entry.source
  end

  def test_empty_and_relative_path_entries_resolve_against_the_current_directory
    exe(@first, "zz-here")
    Dir.chdir(@first) do
      assert_equal File.join(@first, "zz-here"), Hiiro::Catalog.new("zz", path: ":/nonexistent").resolve("here").entry.source
    end
    Dir.chdir(@root) do
      assert_equal File.join(@first, "zz-here"), Hiiro::Catalog.new("zz", path: "first").resolve("here").entry.source
    end
  end

  def test_external_beats_inline_and_inline_names_beat_aliases
    tool = exe(@first, "zz-tool")
    hiiro = Hiiro.new("zz", external_commands: true)
    hiiro.add_subcmd(:tool) {}
    hiiro.add_subcmd(:service, :svc, :tool) {}
    hiiro.add_subcmd(:svc) {}

    with_path(@first) do
      catalog = hiiro.catalog
      assert_equal [["service", "inline", []], ["svc", "inline", []], ["tool", "external", []]],
                   catalog.entries.map { |e| [e.name, e.kind.to_s, e.aliases] }
      assert_equal tool, catalog.resolve("tool").entry.source
      assert_equal [["tool", "inline", nil], ["tool", "inline", "service"]],
                   catalog.resolve("tool").entry.shadowed.map { |c| [c.name, c.kind, c.alias_of] }
      assert_equal [["svc", "inline", "service"]], catalog.resolve("svc").entry.shadowed.map { |c| [c.name, c.kind, c.alias_of] }
    end
  end

  def test_aliases_resolve_to_one_entry_and_prefixes_follow_one_policy
    hiiro = Hiiro.new("zz", external_commands: false)
    hiiro.add_subcmd(:service, :svc) {}
    hiiro.add_subcmd(:session) {}
    hiiro.add_subcmd(:pr) {}
    hiiro.add_subcmd(:"pr-monitor") {}
    catalog = hiiro.catalog

    assert_equal [:exact, "service"], [catalog.resolve("svc").status, catalog.resolve("svc").entry.name]
    assert_equal [:prefix, "service"], [catalog.resolve("sv").status, catalog.resolve("sv").entry.name]
    assert_equal [:ambiguous, %w[service session]], [catalog.resolve("se").status, catalog.resolve("se").candidates.map(&:name)]
    assert_equal [:prefix, "pr"], [catalog.resolve("p").status, catalog.resolve("p").entry.name]
    assert_equal [:prefix, "pr-monitor"], [catalog.resolve("pr-").status, catalog.resolve("pr-").entry.name]
    assert_equal %w[pr pr-monitor service session svc], catalog.complete
    assert_equal %w[service session], catalog.complete("se")
  end

  def test_dispatch_runs_the_resolved_alias_and_reads_path_at_lookup_time
    calls = []
    hiiro = Hiiro.new("zz", "svc", "up", external_commands: false)
    hiiro.add_subcmd(:service, :svc) { |*args| calls << args }
    hiiro.runner.run(*hiiro.args)
    hiiro.run_subcommand(:svc, "down")
    assert_equal [["up"], ["down"]], calls

    exe(@second, "zz-late")
    with_path(@second) { assert_equal "late", Hiiro.new("zz", "la").runner.subcommand_name }
  end

  def test_markdown_and_json_carry_the_same_winners
    tool = exe(@first, "zz-tool")
    shadow = exe(@second, "zz-tool")
    hiiro = Hiiro.new("zz")
    hiiro.add_cmd(:show, :sh, args: %i[name]) {}

    with_path([@first, @second].join(":")) do
      catalog = hiiro.catalog
      source = catalog.resolve("show").entry.source
      assert_equal <<~MD, catalog.to_markdown
        # zz commands

        | Command | Aliases | Kind | Arguments | Source | Origin | Shadowed |
        |---------|---------|------|-----------|--------|--------|----------|
        | show | sh | inline | <name> | #{source} | package hiiro #{Hiiro::VERSION} |  |
        | tool |  | external |  | #{tool} | user | #{shadow} |
      MD
      assert_equal [
        { "name" => "show", "kind" => "inline", "source" => source, "aliases" => ["sh"], "arguments" => "<name>", "shadowed" => [],
          "origin" => "package hiiro #{Hiiro::VERSION}" },
        { "name" => "tool", "kind" => "external", "source" => tool, "aliases" => [], "arguments" => nil,
          "shadowed" => [{ "name" => "tool", "kind" => "external", "source" => shadow, "origin" => "user" }], "origin" => "user" }
      ], JSON.parse(catalog.to_json)
    end
  end

  def test_edit_opens_the_dispatch_winner_and_refuses_ambiguity
    tool = exe(@first, "zz-tool")
    exe(@second, "zz-tool")
    exe(@first, "zz-toad")
    edited = []
    hiiro = Hiiro.new("zz")
    hiiro.define_singleton_method(:edit_files) { |*files| edited << files }

    with_path([@first, @second].join(":")) do
      hiiro.edit_commands("tool")
      error = assert_raises(Hiiro::Error) { hiiro.edit_commands("to") }
      assert_equal 'Ambiguous zz command "to": toad, tool', error.message
      assert_raises(Hiiro::Error) { hiiro.edit_commands("nothing") }
    end
    assert_equal [[tool]], edited
  end

  private

  def dir(name) = File.join(@root, name).tap { |path| FileUtils.mkdir_p(path) }

  def exe(dir, name)
    File.join(dir, name).tap do |path|
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  def with_path(path)
    original = ENV["PATH"]
    ENV["PATH"] = path
    yield
  ensure
    ENV["PATH"] = original
  end
end
