require "test_helper"

class TableTest < Minitest::Test
  include TestHelpers

  def setup
    clear_rows
    @task = Hiiro::TaskRecord.create(name: "alpha")
  end

  def teardown = clear_rows

  def clear_rows
    [Hiiro::RegistryEntry, Hiiro::Tag, Hiiro::TaskRecord].each { |model| model.dataset.delete }
  end

  def test_registry_has_task_id_column
    columns = Hiiro::DB.connection.schema(:registry).map(&:first)

    assert_includes columns, :task_id
  end

  def test_all_lists_tables_sorted
    Hiiro::Table.named("link").add("gh", value: "https://github.com")
    Hiiro::Table.named("dir").add("src", value: "~/src")

    assert_equal %w[dir link], Hiiro::Table.all.map(&:name)
  end

  def test_named_table_without_rows_does_not_exist
    refute Hiiro::Table.named("nothing").exists?
    Hiiro::Table.named("link").add("gh")
    assert Hiiro::Table.named("link").exists?
  end

  def test_add_stores_fields
    entry = Hiiro::Table.named("link").add("gh", value: "v", short: "g", desc: "d", meta: { "k" => 1 }, task_id: @task.id)

    assert_equal ["link", "gh", "v", "g", "d", { "k" => 1 }, @task.id],
      [entry.resource_type, entry.name, entry.value, entry.short_name, entry.description, entry.meta, entry.task_id]
    refute_nil entry.created_at
  end

  def test_entries_by_scope
    link = Hiiro::Table.named("link")
    link.add("b-global", value: "x")
    link.add("a-task", value: "y", task_id: @task.id)
    Hiiro::Table.named("dir").add("other", task_id: @task.id)

    assert_equal ["a-task"], link.entries(scope: Hiiro::TableScope.task(@task)).map(&:name)
    assert_equal ["a-task", "b-global"], link.entries(scope: Hiiro::TableScope.global).map(&:name)
    assert_equal ["a-task", "b-global"], link.entries.map(&:name)
    assert_equal 1, link.count(scope: Hiiro::TableScope.task(@task))
    assert_equal 2, link.count
  end

  def test_find_delegates_to_ref_lookup
    Hiiro::Table.named("link").add("github", short: "gh")
    Hiiro::Table.named("dir").add("github")

    entry = Hiiro::Table.named("link").find("gh")
    assert_equal ["link", "github"], [entry.resource_type, entry.name]
  end

  def test_rename_moves_every_row
    link = Hiiro::Table.named("link")
    link.add("one")
    link.add("two")

    renamed = link.rename("links")

    assert_equal Hiiro::Table.named("links"), renamed
    assert_equal %w[one two], renamed.entries.map(&:name)
    refute Hiiro::Table.named("link").exists?
    assert_equal ["links"], Hiiro::Table.all.map(&:name)
  end

  def test_rename_onto_existing_table_raises
    Hiiro::Table.named("link").add("one")
    Hiiro::Table.named("dir").add("two")

    error = assert_raises(Hiiro::Error) { Hiiro::Table.named("link").rename("dir") }
    assert_equal "table already exists: dir", error.message
    assert_equal ["one"], Hiiro::Table.named("link").entries.map(&:name)
  end

  def test_tag_round_trip
    entry = Hiiro::Table.named("link").add("gh")
    other = Hiiro::Table.named("link").add("other")

    entry.tag("work", "code")
    assert_equal %w[code work], entry.tags
    assert_equal [], other.tags

    entry.untag("work")
    assert_equal %w[code], entry.tags
    assert_equal ["RegistryEntry"], Hiiro::Tag.select_map(:taggable_type)
  end

  def test_current_with_task
    scope = Hiiro::TableScope.current(resolver: -> { @task })

    assert scope.task?
    assert_equal @task.id, scope.task.id
    assert_equal "task(@alpha)", scope.label
  end

  def test_current_without_task
    scope = Hiiro::TableScope.current(resolver: -> { nil })

    assert scope.global?
    assert_nil scope.task
    assert_equal "global", scope.label
  end

  def test_task_requires_record
    assert_raises(ArgumentError) { Hiiro::TableScope.task(nil) }
  end

  def test_toggle_flips_and_keeps_task
    calls = 0
    resolver = -> { calls += 1; @task }

    global = Hiiro::TableScope.task(@task).toggle(resolver:)
    assert_equal ["global", "alpha"], [global.label, global.task.name]

    back = global.toggle(resolver:)
    assert_equal "task(@alpha)", back.label
    assert_equal 0, calls
  end

  def test_toggle_global_resolves_task
    scope = Hiiro::TableScope.global.toggle(resolver: -> { @task })

    assert_equal "task(@alpha)", scope.label
  end

  def test_toggle_without_task_returns_self
    scope = Hiiro::TableScope.global

    assert_same scope, scope.toggle(resolver: -> { nil })
  end

  def test_apply_filters_only_in_task_mode
    Hiiro::Table.named("link").add("mine", task_id: @task.id)
    Hiiro::Table.named("link").add("theirs")
    ds = Hiiro::RegistryEntry.order(:name)

    assert_equal %w[mine], Hiiro::TableScope.task(@task).apply(ds).select_map(:name)
    assert_equal %w[mine theirs], Hiiro::TableScope.global(@task).apply(ds).select_map(:name)
  end

  def test_actions_for_merges_defaults_with_table_override
    actions = Hiiro::TableActions.new("link" => { "o" => "firefox {value}", "c" => "cd {value}" })
    link = Hiiro::Table.named("link").add("gh", value: "x")
    dir = Hiiro::Table.named("dir").add("src", value: "x")

    assert_equal({ "o" => "firefox {value}", "y" => "pbcopy <<< {value}", "c" => "cd {value}" }, actions.for(link))
    assert_equal({ "o" => "open {value}", "y" => "pbcopy <<< {value}" }, actions.for(dir))
  end

  def test_actions_command_escapes_fields
    actions = Hiiro::TableActions.new("dir" => { "e" => "echo {table} {name} {value}" })
    entry = Hiiro::Table.named("dir").add("my src", value: "/tmp/a dir")

    assert_equal "open /tmp/a\\ dir", actions.command("o", entry)
    assert_equal "echo dir my\\ src /tmp/a\\ dir", actions.command("e", entry)
  end

  def test_actions_command_nil_for_unknown_letter
    entry = Hiiro::Table.named("dir").add("src", value: "x")

    assert_nil Hiiro::TableActions.new({}).command("z", entry)
    assert_nil Hiiro::TableActions.new({}).run("z", entry)
  end

  def test_actions_run_executes_command
    with_temp_dir do |dir|
      out = File.join(dir, "out")
      actions = Hiiro::TableActions.new("dir" => { "w" => "printf %s {value} > #{out}" })
      entry = Hiiro::Table.named("dir").add("src", value: "a b")

      assert_equal "printf %s a\\ b > #{out}", actions.run("w", entry)
      assert_equal "a b", File.read(out)
    end
  end

  def test_actions_load_reads_yaml_and_tolerates_missing_file
    entry = Hiiro::Table.named("link").add("gh", value: "x")
    with_temp_file("link:\n  c: cd {value}\n", ".yml") do |path|
      assert_equal "cd x", Hiiro::TableActions.load(path).command("c", entry)
    end

    assert_nil Hiiro::TableActions.load("/nonexistent/tables.yml").command("c", entry)
  end
end
