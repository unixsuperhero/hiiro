class Hiiro
  # Value object representing a git worktree.
  # Tracks path, current HEAD, and branch information.
  class Tree
    attr_reader :path, :head, :branch

    # Get all trees (worktrees) for the default repository.
    #
    # @param repo_path [String] path to the bare repository
    # @return [Array<Tree>] list of trees
    def self.all(repo_path: Hiiro::REPO_PATH)
      git = Hiiro::Git.new(nil, repo_path)
      git.worktrees(repo_path: repo_path).filter_map do |wt|
        next if wt.bare?
        new(path: wt.path, head: wt.head, branch: wt.branch)
      end
    end

    def initialize(path:, head: nil, branch: nil)
      @path = path
      @head = head
      @branch = branch
    end

    # Get the tree name (relative to WORK_DIR or basename).
    #
    # @return [String] the tree name
    def name
      @name ||= if path.start_with?(Hiiro::WORK_DIR + '/')
        path.sub(Hiiro::WORK_DIR + '/', '')
      else
        File.basename(path)
      end
    end

    # Check if a path is within this tree.
    #
    # @param pwd [String] path to check
    # @return [Boolean] true if pwd is within this tree
    def match?(pwd = Dir.pwd)
      pwd == path || pwd.start_with?(path + '/')
    end

    # Check if this tree is in detached HEAD state.
    #
    # @return [Boolean] true if detached
    def detached?
      branch.nil?
    end

    def ==(other)
      other.is_a?(Tree) && path == other.path
    end

    def to_s
      name
    end
  end
end
