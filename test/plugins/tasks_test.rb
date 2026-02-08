require "test_helper"
require_relative "../../plugins/tasks"

class TmuxSessionTest < Minitest::Test
  def test_tmux_session_initialization
    session = TmuxSession.new("my-session")

    assert_equal "my-session", session.name
  end

  def test_tmux_session_to_s
    session = TmuxSession.new("dev")

    assert_equal "dev", session.to_s
  end

  def test_tmux_session_equality
    session1 = TmuxSession.new("test")
    session2 = TmuxSession.new("test")
    session3 = TmuxSession.new("other")

    assert_equal session1, session2
    refute_equal session1, session3
  end

  def test_tmux_session_equality_with_non_session
    session = TmuxSession.new("test")

    refute_equal session, "test"
    refute_equal session, nil
  end
end

class TreeTest < Minitest::Test
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

  def test_task_subtask
    task = Task.new(name: "feature/api", tree: "feature/api")

    assert task.subtask?
    refute task.top_level?
    assert_equal "feature", task.parent_name
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
    assert_equal "feature/api", hash[:name]
    assert_equal "feature", hash[:parent_name]
    assert_equal "api", hash[:short_name]
    assert_equal "feature", hash[:session_name]
    assert_equal "feature/api", hash[:tree_name]
    assert hash[:subtask?]
    refute hash[:top_level?]
  end
end

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

class TaskManagerConfigTest < Minitest::Test
  include TestHelpers

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

  def test_config_remove_task
    with_temp_dir do |dir|
      tasks_dir = File.join(dir, "tasks")
      FileUtils.mkdir_p(tasks_dir)
      tasks_file = File.join(tasks_dir, "tasks.yml")

      # Pre-populate the tasks file with string keys
      File.write(tasks_file, <<~YAML)
        tasks:
          - name: existing-task
            tree: existing-task/main
            session: existing-task
      YAML

      config = TaskManager::Config.new(tasks_file: tasks_file)
      config.remove_task("existing-task")

      content = YAML.load_file(tasks_file, permitted_classes: [Symbol])
      assert_equal 0, content['tasks'].count
    end
  end
end
