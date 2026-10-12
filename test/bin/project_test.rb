require 'test_helper'

class ProjectTest < Minitest::Test
  def setup
    Hiiro::Project.dataset.delete
    @harness = Hiiro::TestHarness.load_bin('bin/h-project')
  end

  def teardown
    Hiiro::Project.dataset.delete
  end

  def test_add_update_remove_preserve_other_aliases_and_ids
    capture_io { @harness.run_subcmd(:add, 'alpha', '/alpha') }
    alpha = Hiiro::Project.find_by_name('alpha')
    capture_io { @harness.run_subcmd(:add, 'beta', '/beta') }
    beta = Hiiro::Project.find_by_name('beta')
    capture_io { @harness.run_subcmd(:add, 'alpha', '/renamed') }
    assert_equal [alpha.id, '/renamed'], Hiiro::Project.find_by_name('alpha').values.values_at(:id, :path)
    capture_io { @harness.run_subcmd(:rm, 'alpha') }
    assert_equal [[beta.id, 'beta', '/beta']], Hiiro::Project.all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_config_shows_canonical_aliases_not_recovery_yaml
    record = Hiiro::Project.create(name: 'alpha', path: '/alpha')
    output, = capture_io { @harness.run_subcmd(:config) }
    assert_equal [{'id' => record.id, 'name' => 'alpha', 'path' => '/alpha'}], YAML.safe_load(output)
  end

  def test_edit_preserves_concurrent_fields_new_rows_and_omitted_rows
    alpha = Hiiro::Project.create(name: 'alpha', path: '/alpha')
    beta = Hiiro::Project.create(name: 'beta', path: '/beta')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      Hiiro::Project[alpha.id].update(path: '/concurrent')
      Hiiro::Project.create(name: 'new', path: '/new')
      rows.first['name'] = 'renamed'
      File.write(path, [rows.first].to_yaml)
      true
    end
    capture_io { @harness.run_subcmd(:edit) }
    assert_equal ['renamed', '/concurrent'], Hiiro::Project[alpha.id].values.values_at(:name, :path)
    assert_equal ['beta', '/beta'], Hiiro::Project[beta.id].values.values_at(:name, :path)
    assert_equal '/new', Hiiro::Project.find_by_name('new').path
  end

  def test_explicit_delete_only_removes_baseline_selection
    alpha = Hiiro::Project.create(name: 'alpha', path: '/alpha')
    beta = Hiiro::Project.create(name: 'beta', path: '/beta')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      Hiiro::Project.create(name: 'new', path: '/new')
      rows.first['delete'] = true
      File.write(path, [rows.first].to_yaml)
      true
    end
    capture_io { @harness.run_subcmd(:edit) }
    assert_nil Hiiro::Project[alpha.id]
    assert_equal [[beta.id, 'beta', '/beta'], [Hiiro::Project.find_by_name('new').id, 'new', '/new']], Hiiro::Project.order(:id).all.map { |row| row.values.values_at(:id, :name, :path) }
  end

  def test_conflicting_edit_rolls_back_prior_changes
    alpha = Hiiro::Project.create(name: 'alpha', path: '/alpha')
    beta = Hiiro::Project.create(name: 'beta', path: '/beta')
    @harness.stub_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      Hiiro::Project[beta.id].update(path: '/concurrent')
      rows.each { |row| row['path'] = '/edited' }
      File.write(path, rows.to_yaml)
      true
    end
    _, error = capture_io { @harness.run_subcmd(:edit) }
    assert_includes error, 'changed while editing'
    assert_equal '/alpha', Hiiro::Project[alpha.id].path
    assert_equal '/concurrent', Hiiro::Project[beta.id].path
  end

  def test_invalid_and_failed_edit_leave_aliases_unchanged
    record = Hiiro::Project.create(name: 'alpha', path: '/alpha')
    [[:invalid, true], [:failed, false], [:cancelled, nil]].each do |kind, status|
      @harness.stub_method(:edit_files) do |path|
        File.write(path, kind == :invalid ? "- name: [\n" : [{'id' => record.id, 'name' => 'changed', 'path' => '/changed'}].to_yaml)
        status
      end
      capture_io { @harness.run_subcmd(:edit) }
      assert_equal ['alpha', '/alpha'], Hiiro::Project[record.id].values.values_at(:name, :path)
    end
  end
end
