require "test_helper"

Workspace = Hiiro::Herdr::Workspace

def herdr_workspace(id, name, path = '/home/user')
  Workspace.new(
    {
      'workspace_id' => id,
      'number' => 1,
      'label' => name,
      'focused' => false,
      'pane_count' => 1,
      'tab_count' => 1,
      'active_tab_id' => "#{id}:t1",
      'agent_status' => 'idle',
      'worktree' => { 'checkout_path' => path },
    }
  )
end

class HerdrWorkspaceTest < Minitest::Test
  def test_workspace_initialization
    workspace = herdr_workspace('w1', 'my-workspace')
    assert_equal 'my-workspace', workspace.name
  end

  def test_workspace_equality_uses_label
    assert_equal herdr_workspace('w1', 'test'), herdr_workspace('w2', 'test')
    refute_equal herdr_workspace('w1', 'test'), herdr_workspace('w3', 'other')
  end

  def test_workspace_path_comes_from_worktree
    workspace = herdr_workspace('w1', 'hiiro', '/Users/josh/proj/hiiro')
    assert_equal '/Users/josh/proj/hiiro', workspace.path
  end
end

Tree = Hiiro::Tree

class TreeTest < Minitest::Test
  WORK_DIR = Hiiro::WORK_DIR
  def test_tree_initialization
    tree = Tree.new(path: "/home/user/work/feature", head: "abc123", branch: "feature")

    assert_equal "/home/user/work/feature", tree.path
    assert_equal "abc123", tree.head
    assert_equal "feature", tree.branch
  end

  def test_tree_name_from_work_dir
    tree = Tree.new(path: "#{WORK_DIR}/my-feature")

    assert_equal "my-feature", tree.name
  end

  def test_tree_name_from_other_path
    tree = Tree.new(path: "/some/other/path/project")

    assert_equal "project", tree.name
  end

  def test_tree_match_exact
    tree = Tree.new(path: "/home/user/project")

    assert tree.match?("/home/user/project")
  end

  def test_tree_match_subpath
    tree = Tree.new(path: "/home/user/project")

    assert tree.match?("/home/user/project/src/main.rb")
  end

  def test_tree_match_different_path
    tree = Tree.new(path: "/home/user/project")

    refute tree.match?("/home/user/other")
    refute tree.match?("/home/user/project-extra")
  end

  def test_tree_detached
    tree_attached = Tree.new(path: "/path", branch: "main")
    tree_detached = Tree.new(path: "/path", branch: nil)

    refute tree_attached.detached?
    assert tree_detached.detached?
  end

  def test_tree_equality
    tree1 = Tree.new(path: "/home/user/project")
    tree2 = Tree.new(path: "/home/user/project")
    tree3 = Tree.new(path: "/home/user/other")

    assert_equal tree1, tree2
    refute_equal tree1, tree3
  end

  def test_tree_to_s
    tree = Tree.new(path: "/home/user/work/my-feature")

    assert_equal tree.name, tree.to_s
  end
end

Task = Hiiro::Task

class TaskTest < Minitest::Test
  def test_task_initialization
    task = Task.new(name: "feature-x", tree: "feature-x/main", session: "feature-x")

    assert_equal "feature-x", task.name
    assert_equal "feature-x/main", task.tree_name
    assert_equal "feature-x", task.session_name
  end

  def test_task_session_defaults_to_name
    task = Task.new(name: "my-task", tree: "my-task/main")

    assert_equal "my-task", task.session_name
  end

  def test_task_top_level
    task = Task.new(name: "feature", tree: "feature/main")

    assert task.top_level?
    refute task.subtask?
    assert_nil task.parent_name
  end

  def test_task_absolute_tree
    task = Task.new(name: "external", tree: "/tmp/external-repo")

    assert task.absolute_tree?
  end

  def test_task_subtask
    task = Task.new(name: "feature/api", tree: "feature/api")

    assert task.subtask?
    refute task.top_level?
    assert_equal "feature", task.parent_name
  end

  def test_external_task_with_slash_name_is_top_level
    task = Task.new(name: "menu/ids", tree: "/tmp/ids-copy")

    refute task.subtask?
    assert task.top_level?
    assert_nil task.parent_name
    assert_equal "menu/ids", task.short_name
  end

  def test_task_short_name_top_level
    task = Task.new(name: "feature", tree: "feature/main")

    assert_equal "feature", task.short_name
  end

  def test_task_short_name_subtask
    task = Task.new(name: "feature/api", tree: "feature/api")

    assert_equal "api", task.short_name
  end

  def test_task_equality
    task1 = Task.new(name: "feature")
    task2 = Task.new(name: "feature")
    task3 = Task.new(name: "other")

    assert_equal task1, task2
    refute_equal task1, task3
  end

  def test_task_to_s
    task = Task.new(name: "my-task")

    assert_equal "my-task", task.to_s
  end

  def test_task_to_h
    task = Task.new(name: "feature/api", tree: "feature/api", session: "feature")

    hash = task.to_h
    # to_h returns serialization-compatible keys for Task.new
    assert_equal "feature/api", hash[:name]
    assert_equal "feature/api", hash[:tree]
    assert_equal "feature", hash[:session]
  end
end

App = Hiiro::App

class AppTest < Minitest::Test
  def test_app_initialization
    app = App.new(name: "frontend", path: "apps/frontend")

    assert_equal "frontend", app.name
    assert_equal "apps/frontend", app.relative_path
  end

  def test_app_resolve
    app = App.new(name: "api", path: "services/api")

    resolved = app.resolve("/home/user/project")

    assert_equal "/home/user/project/services/api", resolved
  end

  def test_app_equality
    app1 = App.new(name: "frontend", path: "apps/frontend")
    app2 = App.new(name: "frontend", path: "apps/frontend")
    app3 = App.new(name: "backend", path: "apps/backend")

    assert_equal app1, app2
    refute_equal app1, app3
  end

  def test_app_to_s
    app = App.new(name: "my-app", path: "path/to/app")

    assert_equal "my-app", app.to_s
  end
end

Environment = Hiiro::Environment

class EnvironmentTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def teardown
    setup
  end

  def test_task_readers_resolve_database_names_and_refresh_changes
    feature = Hiiro::TaskRecord.create(name: 'feature-auth', tree: 'feature-auth/main')
    child = Hiiro::TaskRecord.create(name: 'feature-auth/api', tree: 'feature-auth/api')
    env = Environment.new
    assert_raises(Hiiro::Error) { env.find_task('feat', tty: false) }
    assert_equal 'feature-auth', env.find_task('feature-auth').name
    assert_equal child.id, env.find_task('feature-auth/api').id
    feature.update(next_action: 'Review')
    Hiiro::TaskRecord.create(name: 'bugfix', tree: 'bugfix/main')
    assert_equal %w[bugfix feature-auth feature-auth/api], env.all_tasks.map(&:name)
    assert_equal 'Review', env.find_task('feature-auth').next_action
    assert_nil env.find_task('missing')
  end

  def test_current_task_detects_external_absolute_tree
    with_temp_dir do |dir|
      external = File.join(dir, 'external-repo')
      nested = File.join(external, 'apps', 'api')
      FileUtils.mkdir_p(nested)
      Hiiro::TaskRecord.create(name: 'external', tree: external, session: 'external')
      env = Environment.new(path: nested)
      assert_equal external, env.tree.path
      assert_equal 'external', env.task.name
    end
  end

  def test_app_reader_refreshes_database_aliases
    app = Hiiro::AppRecord.create(name: 'frontend', path: 'apps/frontend')
    env = Environment.new
    assert_equal 'apps/frontend', env.find_app('front').relative_path
    app.update(path: 'apps/ui')
    assert_equal 'apps/ui', env.find_app('front').relative_path
  end

  def test_context_errors_are_not_replaced_with_focused_or_first_tasks
    with_temp_dir do |dir|
      Hiiro::TaskRecord.create(name: 'alpha', primary_directory: dir)
      Hiiro::TaskRecord.create(name: 'alpine', primary_directory: dir)
      env = Environment.new(path: dir)
      assert_raises(Hiiro::Error) { env.task }
      assert_raises(Hiiro::Error) { env.find_task('al', tty: false) }
      selected = env.find_task('al', tty: true, chooser: ->(map) { map.fetch('alpine') })
      assert_equal 'alpine', selected.name
      assert_raises(Hiiro::Error) { env.find_task('al', tty: true, chooser: ->(_map) { nil }) }
    end
  end

  def test_app_selection_is_exact_then_unique_or_mapped_and_cancellation_fails
    Hiiro::AppRecord.create(name: 'web', path: 'apps/web')
    Hiiro::AppRecord.create(name: 'webadmin', path: 'apps/admin')
    env = Environment.new
    assert_equal 'apps/web', env.find_app('web', tty: false).relative_path
    assert_equal 'webadmin', env.find_app('weba', tty: false).name
    assert_raises(Hiiro::Error) { env.find_app('we', tty: false) }
    assert_equal 'webadmin', env.find_app('we', tty: true, chooser: ->(map) { map.fetch('webadmin') }).name
    assert_raises(Hiiro::Error) { env.find_app('we', tty: true, chooser: ->(_map) { nil }) }
  end

  def test_shared_terminal_labels_remain_ambiguous_even_for_exact_reference
    first = Hiiro::TaskRecord.create(name: 'alpha', session: 'shared')
    second = Hiiro::TaskRecord.create(name: 'alpine', session: 'shared')
    records = [first, second]
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.select(records, 'shared', kind: 'task workspace', key: :session, tty: false) }
    selected = Hiiro::CurrentTask.select(records, 'shared', kind: 'task workspace', key: :session, tty: true,
                                         chooser: ->(map) { map.fetch('shared [2]') })
    assert_equal second.id, selected.id
  end
end

TaskManager = Hiiro::TaskManager

class TaskManagerConfigTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def teardown
    setup
  end

  def test_detaching_retains_current_directory_metadata_and_references
    config = TaskManager::Config.new
    record = Hiiro::TaskRecord.create(name: 'existing-task', tree: '/tmp/old', next_action: 'Review', status: 'waiting', waiting_on: 'Feedback')
    config.tasks
    record.update(tree: '/tmp/new')
    issue = Hiiro::TaskResource.create(task_id: record.id, kind: 'issue', target: 'https://example.com/42')
    config.detach_tree(record.name)
    config.detach_tree(record.name)
    assert_nil record.refresh.tree
    assert_equal ['waiting', 'Review', 'Feedback'], record.values.values_at(:status, :next_action, :waiting_on)
    assert_equal [['directory', '/tmp/new'], ['issue', 'https://example.com/42']], record.resources.order(:kind).select_map([:kind, :target])
    assert_equal issue.id, record.resources.where(kind: 'issue').first.id
  end
end

class TaskManagerTasksTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def build_tm(tasks_yaml)
    YAML.safe_load(tasks_yaml).fetch('tasks').each do |attributes|
      Hiiro::TaskRecord.create(attributes.transform_keys(&:to_sym))
    end
    yield TaskManager.new(MockHiiro.new, environment: Hiiro::Environment.new)
  end

  def test_tasks_includes_external_slash_named_tasks
    yaml = <<~YAML
      tasks:
        - { name: menu/ids, tree: /tmp/ids-copy }
        - { name: feature/api, tree: feature/api }
    YAML
    build_tm(yaml) do |tm|
      assert_equal ["menu/ids"], tm.tasks.map(&:name)
    end
  end
end
