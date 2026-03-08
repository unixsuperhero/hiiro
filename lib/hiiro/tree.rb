class Hiiro
  class Tree
    attr_reader :path, :head, :branch

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

    def name
      @name ||= if path.start_with?(Hiiro::WORK_DIR + '/')
        path.sub(Hiiro::WORK_DIR + '/', '')
      else
        File.basename(path)
      end
    end

    def match?(pwd = Dir.pwd)
      pwd == path || pwd.start_with?(path + '/')
    end

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
