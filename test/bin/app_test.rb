require 'test_helper'

class AppTest < Minitest::Test
  def setup
    Hiiro::AppRecord.dataset.delete
    @harness = Hiiro::TestHarness.load_bin('bin/h-app') do
      define_singleton_method(:environment) { Hiiro::Environment.new }
    end
  end

  def teardown
    Hiiro::AppRecord.dataset.delete
  end

  def test_add_list_and_remove_share_canonical_aliases
    capture_io { @harness.run_subcmd(:add, 'frontend', 'apps/frontend') }
    frontend = Hiiro::AppRecord.find_by_name('frontend')
    output, = capture_io { @harness.run_subcmd(:ls) }
    assert_includes output, 'frontend'
    assert_includes output, 'apps/frontend'
    capture_io { @harness.run_subcmd(:add, 'api', 'services/api') }
    api = Hiiro::AppRecord.find_by_name('api')
    capture_io { @harness.run_subcmd(:remove, 'frontend') }
    assert_nil Hiiro::AppRecord[frontend.id]
    assert_equal [[api.id, 'api', 'services/api']], Hiiro::AppRecord.all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_show_is_a_stable_id_database_projection
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    output, = capture_io { @harness.run_subcmd(:show) }
    assert_equal [{'id' => app.id, 'name' => 'frontend', 'path' => 'apps/frontend'}], YAML.safe_load(output)
  end

  def test_edit_changes_selected_fields_without_replacing_aliases
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    other = Hiiro::AppRecord.create(name: 'api', path: 'services/api')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      Hiiro::AppRecord[app.id].update(name: 'concurrent-name')
      Hiiro::AppRecord.create(name: 'worker', path: 'services/worker')
      rows.first['path'] = 'apps/new-frontend'
      File.write(path, [rows.first].to_yaml)
      true
    end
    capture_io { @harness.run_subcmd(:config) }
    assert_equal ['concurrent-name', 'apps/new-frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
    assert_equal ['api', 'services/api'], Hiiro::AppRecord[other.id].values.values_at(:name, :path)
    assert_equal 'services/worker', Hiiro::AppRecord.find_by_name('worker').path
  end

  def test_forged_id_and_invalid_rows_cannot_partially_write
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 'changed'
      rows << {'id' => app.id + 1000, 'name' => 'forged', 'path' => 'forged'}
      File.write(path, rows.to_yaml)
      true
    end
    _, error = capture_io { @harness.run_subcmd(:edit) }
    assert_includes error, 'Unknown or duplicate alias ID'
    assert_equal [[app.id, 'frontend', 'apps/frontend']], Hiiro::AppRecord.all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_semantically_invalid_edit_preserves_existing_aliases
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 42
      File.write(path, rows.to_yaml)
      true
    end
    _, error = capture_io { @harness.run_subcmd(:edit) }
    assert_includes error, 'path must be a nonempty string'
    assert_equal ['frontend', 'apps/frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
  end

  def test_failed_editor_does_not_commit_valid_yaml
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['path'] = 'changed'
      File.write(path, rows.to_yaml)
      false
    end
    capture_io { @harness.run_subcmd(:edit) }
    assert_equal ['frontend', 'apps/frontend'], Hiiro::AppRecord[app.id].values.values_at(:name, :path)
  end
end
