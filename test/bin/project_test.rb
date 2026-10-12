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

  def test_paths_use_exact_project_identity_without_a_task
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      FileUtils.mkdir_p(File.join(root, 'alpha'))
      FileUtils.mkdir_p(File.join(root, 'alphabet'))
      Hiiro::Project.create(name: 'alphabet', path: File.join(root, 'alphabet'))
      Hiiro::Project.create(name: 'alpha', path: File.join(root, 'alpha'))
      @harness.stub_method(:fuzzyfind_from_map) { |_| raise 'Unexpected picker' }
      output, = capture_io { @harness.run_subcmd(:path, 'alpha') }
      assert_equal "#{root}/alpha", output
      context = Hiiro::Projects.new.context('alphab', tty: false)
      assert_equal [nil, 'alphabet', "#{root}/alphabet", :project],
                   [context.task, context.project.name, context.start_directory, context.source]
    end
  end

  def test_unknown_and_ambiguous_project_never_fall_back_to_project_root
    Hiiro::Project.create(name: 'alpha', path: '/missing-alpha')
    Hiiro::Project.create(name: 'alpine', path: '/missing-alpine')
    manager = Hiiro::Projects.new
    assert_raises(Hiiro::Error) { manager.context('al', tty: false) }
    assert_raises(Hiiro::Error) { manager.context('unknown', tty: false) }
    assert_raises(Hiiro::Error) { manager.context('alpha', tty: false) }
  end

  def test_ambiguous_project_picker_returns_mapped_identity_and_cancellation_fails
    Hiiro::Project.create(name: 'alpha', path: '/alpha')
    Hiiro::Project.create(name: 'alpine', path: '/alpine')
    manager = Hiiro::Projects.new
    chosen = manager.resolve('al', tty: true, chooser: ->(mapping) { mapping.values.find { |item| item.first == 'alpine' } })
    assert_equal ['alpine', '/alpine'], chosen
    assert_raises(Hiiro::Error) { manager.resolve('al', tty: true, chooser: ->(_) { nil }) }
    assert_raises(Hiiro::Error) { manager.resolve('al', tty: true, chooser: ->(_) { ['forged', '/elsewhere'] }) }
  end

  def test_omitted_project_selector_keeps_taskless_project_root
    Dir.mktmpdir do |directory|
      home = File.realpath(directory)
      root = File.join(home, 'proj')
      FileUtils.mkdir_p(root)
      Dir.stub(:home, home) do
        selected = Hiiro::Projects.new.context
        assert_equal [nil, 'proj', root, :project],
                     [selected.task, selected.project, selected.start_directory, selected.source]
        assert_raises(Hiiro::Error) { Hiiro::Projects.new.context('') }
      end
    end
  end
end
