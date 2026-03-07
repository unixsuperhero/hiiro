class Hiiro
  # Value object representing an app directory within a task/tree.
  # Maps app names to relative paths within the git worktree.
  class App
    attr_reader :name, :relative_path

    def initialize(name:, path:)
      @name = name
      @relative_path = path
    end

    # Resolve the app's absolute path within a tree root.
    #
    # @param tree_root [String] the tree/worktree root path
    # @return [String] absolute path to the app
    def resolve(tree_root)
      File.join(tree_root, relative_path)
    end

    def ==(other)
      other.is_a?(App) && name == other.name
    end

    def to_s
      name
    end
  end
end
