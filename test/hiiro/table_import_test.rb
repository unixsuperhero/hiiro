require_relative "../test_helper"

# Legacy pins: the retired `pins` table moves into registry tables at setup
# (Hiiro::DB.import_legacy_tables!); pin files and sounds.yml are explicit
# `h db migrate` inputs that are retained byte-identical.
class TableImportTest < Minitest::Test
  def setup
    clear
    @base = Dir.mktmpdir("hiiro-table-import-")
    FileUtils.mkdir_p(File.join(@base, "pins"))
    File.write(File.join(@base, "pins", "h-sha"), "old: abc\n'102': def\n")
    File.write(File.join(@base, "sounds.yml"), "# system sounds\n# name: path\nbasso: /S/Basso.aiff\ntink: /S/Tink.aiff\n")

    db = Hiiro::DB.connection
    db.drop_table?(:pins)
    db.create_table(:pins) do
      primary_key :id
      String :command, null: false
      String :key, null: false
      String :value_json
    end
    db[:pins].insert(command: "t", key: "current_task", value_json: "7")
  end

  def teardown
    FileUtils.remove_entry(@base)
    Hiiro::DB.connection.drop_table?(:pins)
    clear
  end

  def clear
    Hiiro::RegistryEntry.dataset.delete
    Hiiro::TaskRecord.dataset.delete
    db = Hiiro::DB.connection
    db[:migration_rows].delete
    db[:migration_sources].delete
    db[:schema_migrations].where(name: 'owned_yaml_import_v1').delete
  end

  def pairs(table) = Hiiro::Table.named(table).entries.map { |e| [e.name, e.value] }

  def test_imports_pins_table_pin_files_and_sounds_once
    Hiiro::DB.import_legacy_tables!
    Hiiro::DB.migrate!(only: %i[pins sounds], base: @base)

    assert_equal %w[sha sound t], Hiiro::Table.all.map(&:name)
    assert_equal [["102", "def"], ["old", "abc"]], pairs("sha")
    assert_equal [["basso", "/S/Basso.aiff"], ["tink", "/S/Tink.aiff"]], pairs("sound")
    assert_equal "7", Hiiro::Table.named("t").find("current_task").value
    assert Hiiro::DB.connection.table_exists?(:pins), 'retired pins table is left in place'
    assert File.exist?(File.join(@base, "pins", "h-sha")), 'sources are retained'
    assert File.exist?(File.join(@base, "sounds.yml"))

    count = Hiiro::RegistryEntry.count
    Hiiro::DB.import_legacy_tables!
    report = Hiiro::DB.migrate!(only: %i[pins sounds], base: @base)
    assert_equal count, Hiiro::RegistryEntry.count
    assert_equal %w[previously-applied previously-applied], report.map { |entry| entry[:status] }
  end

  def test_save_current_round_trips_through_current_task_pin
    cli = Object.new.extend(Hiiro::TaskCli::Commands)
    first = Hiiro::TaskRecord.create(name: "first")
    second = Hiiro::TaskRecord.create(name: "second")

    cli.save_current(first)
    assert_equal "first", Hiiro::CurrentTask.new(cwd: @base, pin: true).resolve!.name

    cli.save_current(second)
    assert_equal "second", Hiiro::CurrentTask.new(cwd: @base, pin: true).resolve!.name
    assert_equal [["current_task", second.id.to_s]], pairs("t")
  end
end
