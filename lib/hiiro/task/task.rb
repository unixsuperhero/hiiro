class Hiiro
  # Value object representing a task (development context/project).
  # Links a task name to a git worktree and tmux session.
  class Task
    attr_reader :name, :tree_name, :session_name

    def initialize(name:, tree: nil, session: nil, **)
      @name = name
      @tree_name = tree
      @session_name = session || name
    end

    # --- Name Accessors ---

    def parent_name
      return nil unless subtask?
      name.split('/').first
    end

    def short_name
      subtask? ? name.split('/', 2).last : name
    end

    # --- Predicates ---

    def subtask?
      name.include?('/')
    end

    def top_level?
      !subtask?
    end

    # --- Context-dependent methods (receive environment) ---

    # Get the tree object for this task.
    #
    # @param environment [Environment] the environment to resolve against
    # @return [Tree, nil] the tree or nil
    def tree(environment = nil)
      environment ||= Environment.current rescue nil
      return nil unless environment
      environment.find_tree(tree_name)
    end

    # Get the branch for this task.
    #
    # @param environment [Environment] the environment to resolve against
    # @return [String, nil] the branch name or nil
    def branch(environment = nil)
      tree(environment)&.branch
    end

    # --- Actor Methods ---

    # Switch to this task.
    #
    # @param manager [TaskManager] the task manager
    # @param app_name [String, nil] optional app to open
    # @return [void]
    def switch(manager:, app_name: nil)
      TaskSwitch.new(manager, self, app_name: app_name).call
    end

    # --- Comparison ---

    def ==(other)
      other.is_a?(Task) && name == other.name
    end

    def to_s
      name
    end

    # --- Serialization ---

    def to_h
      h = { name: name }
      h[:tree] = tree_name if tree_name
      h[:session] = session_name if session_name != name
      h
    end

    # --- Display ---

    def display_line(scope: :task, environment:)
      display_name = (scope == :subtask) ? short_name : name
      tree_obj = environment.find_tree(tree_name)
      branch_name = tree_obj&.branch || (tree_obj&.detached? ? '(detached)' : '(none)')
      session = session_name || '(none)'

      format("%-25s  tree: %-20s  branch: %-20s  session: %s",
             display_name,
             tree_name || '(none)',
             branch_name,
             session)
    end
  end
end
