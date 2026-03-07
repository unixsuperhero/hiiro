class Hiiro
  # Orchestrates switching to an existing task.
  # Resumes or creates a tmux session for the task.
  class TaskSwitch
    attr_reader :manager, :task, :app_name

    def initialize(manager, task, app_name: nil)
      @manager = manager
      @task = task
      @app_name = app_name
    end

    # Execute the switch process.
    #
    # @return [void]
    def call
      tree_path = manager.task_path(task)
      session_name = task.session_name
      session_exists = system('tmux', 'has-session', '-t', session_name, err: File::NULL)

      if session_exists
        manager.hiiro.start_tmux_session(session_name)
      else
        base_dir = base_dir_path(tree_path)
        if Dir.exist?(base_dir)
          Dir.chdir(base_dir)
          manager.hiiro.start_tmux_session(session_name)
        else
          puts "ERROR: Path '#{base_dir}' does not exist"
          return
        end
      end

      puts "Switched to '#{task.name}'"
    end

    private

    # Get the base directory path (noun-named per Phase 5).
    def base_dir_path(tree_path)
      if app_name
        app = manager.environment.find_app(app_name)
        app ? app.resolve(tree_path) : tree_path
      else
        tree_path
      end
    end

  end
end
