class Hiiro
  # Presentation layer for task output formatting.
  module TaskPresenter
    module_function

    # Print the task list.
    #
    # @param tm [TaskManager::Manager] the task manager
    def print_list(tm)
      items = tm.tasks
      if items.empty?
        puts tm.scope == :subtask ? "No subtasks found" : "No tasks found"
        puts "Use 'h #{tm.scope} start NAME' to create one."
        return
      end

      current = tm.current_task
      label = build_label(tm)

      puts "#{label}:"
      puts

      items.each do |task|
        print_task_line(task, current, tm)
      end

      print_available_trees(tm)
    end

    def print_task_line(task, current, tm)
      marker = (current && current.name == task.name) ? "*" : " "
      line = task.display_line(scope: tm.scope, environment: tm.environment)
      puts "#{marker} #{line}"

      return unless tm.scope == :task

      tm.subtasks(task).each do |st|
        sub_marker = (current && current.name == st.name) ? "*" : " "
        sub_line = st.display_line(scope: :subtask, environment: tm.environment)
        puts "#{sub_marker} - #{sub_line}"
      end
    end

    def print_available_trees(tm)
      available = tm.environment.all_trees.reject { |t|
        tm.environment.all_tasks.any? { |task| task.tree_name == t.name }
      }

      return unless available.any?

      puts
      available.each do |tree|
        branch_str = tree.branch ? "  [#{tree.branch}]" : tree.detached? ? "  [(detached)]" : ""
        puts format("  %-25s  (available)%s", tree.name, branch_str)
      end
    end

    def build_label(tm)
      if tm.scope == :subtask && tm.current_task
        parent = tm.send(:current_parent_task)
        parent ? "Subtasks of '#{parent.name}'" : "Subtasks"
      else
        tm.scope == :subtask ? "Subtasks" : "Tasks"
      end
    end

    # Print task status.
    #
    # @param task [Task] the task
    # @param environment [Environment] the environment
    def print_status(task, environment)
      unless task
        puts "Not currently in a task session"
        return
      end

      puts "Task: #{task.name}"
      puts "Worktree: #{task.tree_name}"
      tree = environment.find_tree(task.tree_name)
      puts "Path: #{tree&.path || '(unknown)'}"
      puts "Session: #{task.session_name}"
      puts "Parent: #{task.parent_name}" if task.subtask?
    end

    # Print app list.
    #
    # @param apps [Array<App>] list of apps
    def print_apps(apps)
      if apps.any?
        puts "Configured apps:"
        puts
        apps.each do |app|
          puts format("  %-20s => %s", app.name, app.relative_path)
        end
      else
        puts "No apps configured."
        puts "Create #{TaskManager::Config::APPS_FILE} with format:"
        puts "  app_name: relative/path/from/repo"
      end
    end
  end
end
