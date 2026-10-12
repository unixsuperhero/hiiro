require 'test_helper'

class OtaskPersistenceTest < Minitest::Test
  class Registration
    def add_subcmd(*) = nil
    def run = nil
  end

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::Assignment.dataset.delete
    Hiiro::AppRecord.dataset.delete
    namespace = Module.new
    namespace.const_set(:Tmux, Module.new)
    Hiiro.stub(:init, Registration.new) do
      namespace.module_eval(File.read(File.expand_path('../../bin/h-otask', __dir__)), 'bin/h-otask')
    end
    @manager = namespace.const_get(:TaskManager).new(nil)
  end

  def teardown
    Hiiro::TaskRecord.dataset.delete
    Hiiro::Assignment.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def test_interleaved_assignments_preserve_identity_and_unrelated_records
    @manager.assign_task_to_tree('alpha', 'alpha/main')
    selected = Hiiro::Assignment.for_worktree('alpha/main')
    task = Hiiro::TaskRecord.find_by_name('alpha')
    @manager.assignments
    unrelated = Hiiro::Assignment.create(worktree: 'beta/main', branch: 'beta')
    task.update(next_action: 'Review', status: 'waiting')
    @manager.assign_task_to_tree('alpha', 'alpha/main')
    assert_equal selected.id, Hiiro::Assignment.for_worktree('alpha/main').id
    assert_equal task.id, Hiiro::TaskRecord.find_by_name('alpha').id
    assert_equal ['waiting', 'Review'], task.refresh.values.values_at(:status, :next_action)
    @manager.unassign_task_from_tree('alpha/main')
    assert_nil Hiiro::Assignment[selected.id]
    assert_equal 'beta', Hiiro::Assignment[unrelated.id].branch
    assert_nil task.refresh.tree
    assert_equal File.join(Hiiro::WORK_DIR, 'alpha/main'), task.resources.where(kind: 'directory').first.target
  end

  def test_task_detail_updates_preserve_saved_windows_and_other_metadata
    @manager.assign_task_to_tree('alpha', 'alpha/main')
    task = Hiiro::TaskRecord.find_by_name('alpha')
    windows = [{ 'index' => '0', 'name' => 'vim', 'path' => '/tmp/code' }]
    @manager.save_task_metadata('alpha', windows: windows, saved_at: 'yesterday', custom: false)
    task.metadata = task.refresh.metadata.merge('other' => ['42'])
    task.set(next_action: 'Review', app: 'api')
    task.save_changes
    resource = Hiiro::TaskResource.create(task_id: task.id, kind: 'link', target: 'https://example.com')
    @manager.save_task_metadata('alpha', tree: 'alpha/other', session: 'alpha')
    assert_equal({ 'windows' => windows, 'saved_at' => 'yesterday', 'custom' => false, 'other' => ['42'] }, task.refresh.metadata)
    assert_equal ['Review', 'api', 'alpha/other'], task.values.values_at(:next_action, :app, :tree)
    assert_equal resource.id, task.resources.where(kind: 'link').first.id
    assert_equal 'yesterday', @manager.task_metadata('alpha')['saved_at']
  end

  def test_detail_save_does_not_recreate_missing_tasks
    error = assert_raises(Hiiro::Error) { @manager.save_task_metadata('removed', windows: []) }
    assert_equal 'Task not found: removed', error.message
    @manager.assign_task_to_tree('present', 'present/main')
    assert_equal ['present'], Hiiro::TaskRecord.select_map(:name)
  end

  def test_legacy_apps_read_database_aliases
    Hiiro::AppRecord.create(name: 'api', path: 'apps/api')
    assert_equal({ 'api' => 'apps/api' }, @manager.apps_config)
  end
end
