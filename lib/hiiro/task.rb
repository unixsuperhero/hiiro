class Hiiro
  class Task
    attr_reader :name, :tree_name, :session_name

    def initialize(name:, tree: nil, session: nil, **_)
      @name = name
      @tree_name = tree
      @session_name = session || name
    end

    def parent_name
      return nil unless subtask?
      name.split('/').first
    end

    def short_name
      subtask? ? name.split('/', 2).last : name
    end

    def subtask?
      name.include?('/')
    end

    def top_level?
      !subtask?
    end

    def tree
      @tree ||= Environment.current&.find_tree(tree_name)
    end

    def branch
      tree&.branch
    end

    def ==(other)
      other.is_a?(Task) && name == other.name
    end

    def to_s
      name
    end

    def to_h
      h = { name: name }
      h[:tree] = tree_name if tree_name
      h[:session] = session_name if session_name != name
      h
    end

    def display_line(scope: :task, environment:)
      display_name = (scope == :subtask) ? short_name : name
      tree = environment.find_tree(tree_name)
      branch = tree&.branch || (tree&.detached? ? '(detached)' : '(none)')
      session = session_name || '(none)'

      format("%-25s  tree: %-20s  branch: %-20s  session: %s",
             display_name,
             tree_name || '(none)',
             branch,
             session)
    end
  end
end
