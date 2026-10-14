require 'test_helper'

class ProjectTest < Minitest::Test
  def setup
    Hiiro::RegistryEntry.where(resource_type: 'project').delete
    @harness = Hiiro::TestHarness.load_bin('bin/h-project')
  end

  def teardown
    Hiiro::RegistryEntry.where(resource_type: 'project').delete
  end

  def aliases = Hiiro::RegistryEntry.where(resource_type: 'project').order(:id).all.map { |row| row.values.values_at(:id, :name, :value) }
  def find(name) = Hiiro::RegistryEntry.where(resource_type: 'project', name: name).first
  def add(name, path) = Hiiro::Table.named('project').add(name, value: path)

  def test_registers_expected_subcommands
    expected = %i[open list ls add rm config edit select copy sh ui help]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_add_update_remove_preserve_other_aliases_and_ids
    capture_io { @harness.run_subcmd(:add, 'alpha', '/alpha') }
    alpha = find('alpha')
    capture_io { @harness.run_subcmd(:add, 'beta', '/beta') }
    beta = find('beta')
    capture_io { @harness.run_subcmd(:add, 'alpha', '/renamed') }
    assert_equal [alpha.id, '/renamed'], find('alpha').values.values_at(:id, :value)
    capture_io { @harness.run_subcmd(:rm, 'alpha') }
    assert_equal [[beta.id, 'beta', '/beta']], aliases
  end

  def test_config_shows_saved_aliases_as_yaml
    output, = capture_io { @harness.run_subcmd(:config) }
    assert_includes output, 'No project aliases saved.'
    add('beta', '/beta')
    add('alpha', '/alpha')
    output, = capture_io { @harness.run_subcmd(:config) }
    assert_equal "alpha: /alpha\nbeta: /beta\n", output
  end

  def test_edit_updates_adds_and_removes_aliases_by_name
    alpha = add('alpha', '/alpha')
    add('beta', '/beta')
    @harness.stub_method(:edit_files) do |path|
      File.write(path, "alpha: /edited\nnew: /new\n")
      true
    end
    capture_io { @harness.run_subcmd(:edit) }
    assert_equal [[alpha.id, 'alpha', '/edited'], [find('new').id, 'new', '/new']], aliases
  end

  def test_invalid_empty_and_failed_edit_leave_aliases_unchanged
    record = add('alpha', '/alpha')
    [[:invalid, true], [:empty, true], [:failed, false]].each do |kind, status|
      @harness.stub_method(:edit_files) do |path|
        File.write(path, kind == :invalid ? "- name: [\n" : kind == :empty ? "" : "alpha: /changed\n")
        status
      end
      output, = capture_io { @harness.run_subcmd(:edit) }
      assert_includes output, 'No changes applied.'
      assert_equal [[record.id, 'alpha', '/alpha']], aliases
    end
  end

  def test_paths_use_exact_project_identity_without_a_task
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      FileUtils.mkdir_p(File.join(root, 'alpha'))
      FileUtils.mkdir_p(File.join(root, 'alphabet'))
      add('alphabet', File.join(root, 'alphabet'))
      add('alpha', File.join(root, 'alpha'))
      @harness.stub_method(:fuzzyfind_from_map) { |_| raise 'Unexpected picker' }
      output, = capture_io { @harness.run_subcmd(:path, 'alpha') }
      assert_equal "#{root}/alpha", output
      context = Hiiro::Projects.new.context('alphab', tty: false)
      assert_equal [nil, 'alphabet', "#{root}/alphabet", :project],
                   [context.task, context.project.name, context.start_directory, context.source]
    end
  end

  def test_unknown_and_ambiguous_project_never_fall_back_to_project_root
    add('alpha', '/missing-alpha')
    add('alpine', '/missing-alpine')
    manager = Hiiro::Projects.new
    assert_raises(Hiiro::Error) { manager.context('al', tty: false) }
    assert_raises(Hiiro::Error) { manager.context('unknown', tty: false) }
    assert_raises(Hiiro::Error) { manager.context('alpha', tty: false) }
  end

  def test_ambiguous_project_picker_returns_mapped_identity_and_cancellation_fails
    add('alpha', '/alpha')
    add('alpine', '/alpine')
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
