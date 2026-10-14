require_relative "../test_helper"

class ProjectImportTest < Minitest::Test
  def setup
    clear
    @base = Dir.mktmpdir("hiiro-project-import-")
    File.write(File.join(@base, "projects.yml"), "# project aliases\nane: vc/ane\n")

    db = Hiiro::DB.connection
    db.drop_table?(:projects)
    db.create_table(:projects) do
      primary_key :id
      String :name, null: false
      String :path, null: false
    end
    db[:projects].insert(name: "hiiro", path: "/p/hiiro")
  end

  def teardown
    FileUtils.remove_entry(@base)
    Hiiro::DB.connection.drop_table?(:projects)
    clear
  end

  def clear
    Hiiro::RegistryEntry.dataset.delete
    db = Hiiro::DB.connection
    db[:migration_rows].delete
    db[:migration_sources].delete
    db[:schema_migrations].where(name: 'owned_yaml_import_v1').delete
  end

  def pairs = Hiiro::Table.named("project").entries.map { |e| [e.name, e.value] }

  def test_imports_projects_table_and_yaml_once
    Hiiro::DB.import_legacy_tables!
    Hiiro::DB.migrate!(only: [:projects], base: @base)

    assert_equal [["ane", "vc/ane"], ["hiiro", "/p/hiiro"]], pairs
    assert File.exist?(File.join(@base, "projects.yml")), "sources are retained"
    assert Hiiro::DB.connection.table_exists?(:projects), "retired projects table is left in place"

    count = Hiiro::RegistryEntry.count
    Hiiro::DB.import_legacy_tables!
    Hiiro::DB.migrate!(only: [:projects], base: @base)
    assert_equal count, Hiiro::RegistryEntry.count
  end

  def test_from_config_and_save_project
    Hiiro::DB.import_legacy_tables!
    Hiiro::DB.migrate!(only: [:projects], base: @base)
    projects = Hiiro::Projects.new

    assert_equal({ "ane" => "vc/ane", "hiiro" => "/p/hiiro" }, projects.from_config)

    projects.save_project("ane", "/p/ane")
    assert_equal({ "ane" => "/p/ane", "hiiro" => "/p/hiiro" }, projects.from_config)

    projects.save_project("an", "/p/an")
    assert_equal({ "an" => "/p/an", "ane" => "/p/ane", "hiiro" => "/p/hiiro" }, projects.from_config)
  end
end
