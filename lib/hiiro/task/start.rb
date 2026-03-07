require 'fileutils'

class Hiiro
  # Orchestrates starting a new task.
  # Creates/reuses a worktree and tmux session.
  class TaskStart
    attr_reader :manager, :name, :app_name

    def initialize(manager, name, app_name: nil)
      @manager = manager
      @name = name
      @app_name = app_name
    end

    # Execute the start process.
    #
    # @return [void]
    def call
      task_name_val = task_name
      subtree_name_val = subtree_name
      target_path = File.join(Hiiro::WORK_DIR, subtree_name_val)

      unless setup_worktree(target_path)
        return
      end

      session_name = task_name_val
      task = Task.new(name: task_name_val, tree: subtree_name_val, session: session_name)
      manager.config.save_task(task)

      base_dir = base_dir_path(target_path)
      Dir.chdir(base_dir)
      manager.hiiro.start_tmux_session(session_name)

      puts "Started task '#{task_name_val}' in worktree '#{subtree_name_val}'"
    end

    # Alias for backwards compatibility
    alias_method :execute, :call

    private

    # Generate the task name (noun-named per Phase 5).
    def task_name
      manager.scope == :subtask ? "#{current_parent.name}/#{name}" : name
    end

    # Generate the subtree name (noun-named per Phase 5).
    def subtree_name
      manager.scope == :subtask ? "#{current_parent.name}/#{name}" : "#{name}/main"
    end

    # Backwards compatibility aliases
    alias_method :build_task_name, :task_name
    alias_method :build_subtree_name, :subtree_name

    def current_parent
      manager.send(:current_parent_task)
    end

    def setup_worktree(target_path)
      git = Hiiro::Git.new(nil, Hiiro::REPO_PATH)
      available = manager.available_tree

      if available
        puts "Renaming worktree '#{available.name}' to '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.move_worktree(available.path, target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to rename worktree"
          return false
        end
      else
        puts "Creating new worktree '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.add_worktree_detached(target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to create worktree"
          return false
        end
      end
      true
    end

    # Get the base directory path (noun-named per Phase 5).
    def base_dir_path(target_path)
      if app_name
        app = manager.environment.find_app(app_name)
        app ? app.resolve(target_path) : target_path
      else
        target_path
      end
    end

    # Backwards compatibility alias
    alias_method :resolve_base_dir, :base_dir_path
  end
end
