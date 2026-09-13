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

  def test_current_returns_environment_with_pwd
    env = Environment.current

    assert_instance_of Environment, env
    assert_equal Dir.pwd, env.path
  end

  def test_initialize_with_custom_path
    env = Environment.new(path: "/custom/path")

    assert_equal "/custom/path", env.path
  end

  def test_all_tasks_returns_tasks_from_config
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: task-one
            tree: task-one/main
          - name: task-two
            tree: task-two/main
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(config: config)

      assert_equal 2, env.all_tasks.count
      assert_equal "task-one", env.all_tasks.first.name
    end
  end

  def test_find_task_by_full_name
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: feature
            tree: feature/main
          - name: bugfix
            tree: bugfix/main
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(config: config)

      task = env.find_task("feature")

      assert_equal "feature", task.name
    end
  end

  def test_find_task_by_prefix
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: feature-auth
            tree: feature-auth/main
          - name: bugfix
            tree: bugfix/main
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(config: config)

      task = env.find_task("feat")

      assert_equal "feature-auth", task.name
    end
  end

  def test_find_task_returns_nil_for_no_match
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, "tasks: []\n")

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(config: config)

      task = env.find_task("nonexistent")

      assert_nil task
    end
  end

  def test_current_task_detects_external_absolute_tree
    Hiiro::TaskRecord.dataset.delete

    with_temp_dir do |dir|
      external_tree = File.join(dir, "external-repo")
      nested_path = File.join(external_tree, "apps", "api")
      FileUtils.mkdir_p(nested_path)

      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: external
            tree: #{external_tree}
            session: external
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(path: nested_path, config: config)

      assert_equal external_tree, env.tree.path
      assert_equal "external", env.task.name
    end
  end

  def test_find_task_with_slash_path
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: feature
            tree: feature/main
          - name: feature/api
            tree: feature/api
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Environment.new(config: config)

      task = env.find_task("feature/api")

      assert_equal "feature/api", task.name
    end
  end

  def test_task_matcher_returns_matcher_instance
    env = Environment.new(config: TaskManager::Config.new(tasks_file: "/nonexistent"))

    matcher = env.task_matcher

    assert_instance_of Hiiro::Matcher, matcher
  end

  def test_session_matcher_with_stubbed_sessions
    env = Environment.new

    stub_workspaces = [
      herdr_workspace('w1', 'work', '/home/user/work'),
      herdr_workspace('w2', 'personal', '/home/user/personal'),
    ]
    client = Struct.new(:workspaces).new(stub_workspaces)
    Hiiro::Herdr.stub(:client, client) do
      # Force reload
      env.instance_variable_set(:@all_sessions, nil)
      matcher = env.session_matcher

      assert_instance_of Hiiro::Matcher, matcher
    end
  end
end

TaskManager = Hiiro::TaskManager

class TaskManagerFromWorktreeTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def teardown
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def test_task_from_worktree_registers_existing_git_worktree
    with_temp_dir do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      assert system('git', 'init', '-q', repo)

      tasks_dir = File.join(dir, "tasks")
      tasks_file = File.join(tasks_dir, "tasks.yml")
      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Hiiro::Environment.new(config: config)
      tm = TaskManager.new(MockHiiro.new, environment: env)

      task = nil
      out, = capture_io do
        task = tm.task_from_worktree(repo, "external")
      end

      expected_root = `git -C #{repo.shellescape} rev-parse --show-toplevel`.strip
      assert_equal "external", task.name
      assert_equal expected_root, task.tree_name
      assert_equal expected_root, tm.resolve_path(task)
      assert_match "Added task 'external' from worktree '#{expected_root}'", out
    end
  end

  def test_task_from_worktree_rejects_non_git_directory
    with_temp_dir do |dir|
      config = TaskManager::Config.new(tasks_file: File.join(dir, "tasks", "tasks.yml"))
      env = Hiiro::Environment.new(config: config)
      tm = TaskManager.new(MockHiiro.new, environment: env)

      task = nil
      out, = capture_io do
        task = tm.task_from_worktree(dir, "external")
      end

      assert_nil task
      assert_match "is not inside a git worktree", out
    end
  end
end

class TaskManagerConfigTest < Minitest::Test
  include TestHelpers

  def setup
    # Clear SQLite task/app data so tests that pass explicit YAML files get clean results
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def test_config_apps_from_yaml
    with_temp_dir do |dir|
      apps_file = File.join(dir, "apps.yml")
      File.write(apps_file, <<~YAML)
        frontend: apps/frontend
        backend: services/backend
      YAML

      config = TaskManager::Config.new(apps_file: apps_file)
      apps = config.apps

      assert_equal 2, apps.count
      assert_equal "frontend", apps.first.name
      assert_equal "apps/frontend", apps.first.relative_path
    end
  end

  def test_config_apps_empty_when_no_file
    config = TaskManager::Config.new(apps_file: "/nonexistent/file.yml")
    apps = config.apps

    assert_equal [], apps
  end

  def test_config_tasks_from_yaml
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: feature-x
            tree: feature-x/main
            session: feature-x
          - name: feature-x/api
            tree: feature-x/api
            session: feature-x
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      tasks = config.tasks

      assert_equal 2, tasks.count
      assert_equal "feature-x", tasks.first.name
      assert_equal "feature-x/api", tasks.last.name
    end
  end

  def test_config_save_task
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")

      config = TaskManager::Config.new(tasks_file: tasks_file)

      task = Task.new(name: "new-task", tree: "new-task/main", session: "new-task")
      config.save_task(task)

      # Verify file was saved
      assert File.exist?(tasks_file)
      content = YAML.load_file(tasks_file, permitted_classes: [Symbol])
      assert_equal 1, content['tasks'].count
    end
  end

  def test_detaching_a_worktree_preserves_task_metadata_and_references
    with_temp_dir do |dir|
      config = TaskManager::Config.new(tasks_file: File.join(dir, 'tasks.yml'))
      task = Task.new(name: 'existing-task', tree: dir, next_action: 'Review the design', status: 'waiting', waiting_on: 'Feedback')
      config.save_task(task)
      record = Hiiro::TaskRecord.find_by_name(task.name)
      Hiiro::TaskResource.create(task_id: record.id, kind: 'issue', target: 'https://example.com/issue/42')

      config.detach_tree(task.name)
      config.detach_tree(task.name)
      loaded = config.tasks.find { |item| item.name == task.name }
      config.save_task(loaded)

      assert_nil loaded.tree_name
      assert_equal 'waiting', loaded.status
      assert_equal 'Review the design', loaded.next_action
      assert_equal 'Feedback', loaded.waiting_on
      assert_equal [
        ['directory', dir],
        ['issue', 'https://example.com/issue/42']
      ], record.resources.order(:kind).select_map([:kind, :target])
    end
  end
end

class TaskManagerFilterTasksTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def build_tm(tasks_yaml)
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")
      File.write(tasks_file, tasks_yaml)
      config = TaskManager::Config.new(tasks_file: tasks_file)
      env = Hiiro::Environment.new(config: config)
      yield TaskManager.new(MockHiiro.new, environment: env)
    end
  end

  def test_filter_tasks_returns_all_when_no_prefixes
    yaml = <<~YAML
      tasks:
        - { name: alpha, tree: alpha/main }
        - { name: beta,  tree: beta/main }
        - { name: gamma, tree: gamma/main }
    YAML
    build_tm(yaml) do |tm|
      assert_equal %w[alpha beta gamma], tm.filter_tasks.map(&:name)
    end
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

  def test_filter_tasks_filters_by_prefix
    yaml = <<~YAML
      tasks:
        - { name: feature-auth, tree: feature-auth/main }
        - { name: feature-api,  tree: feature-api/main }
        - { name: bugfix,       tree: bugfix/main }
    YAML
    build_tm(yaml) do |tm|
      assert_equal %w[feature-api feature-auth], tm.filter_tasks(["feat"]).map(&:name)
    end
  end

  def test_filter_tasks_ors_multiple_prefixes
    yaml = <<~YAML
      tasks:
        - { name: feature-auth, tree: feature-auth/main }
        - { name: bugfix,       tree: bugfix/main }
        - { name: chore,        tree: chore/main }
    YAML
    build_tm(yaml) do |tm|
      assert_equal %w[bugfix feature-auth], tm.filter_tasks(["feat", "bug"]).map(&:name)
    end
  end

  def test_filter_tasks_returns_empty_for_no_match
    yaml = "tasks:\n  - { name: alpha, tree: alpha/main }\n"
    build_tm(yaml) do |tm|
      assert_empty tm.filter_tasks(["zzz"])
    end
  end
end
