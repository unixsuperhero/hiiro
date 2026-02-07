class Hiiro
  class Git
    class Worktrees
      include Enumerable

      def self.from_porcelain(output)
        return new([]) if output.nil? || output.empty?

        blocks = []
        current_block = []

        output.each_line do |line|
          line = line.chomp
          if line.empty?
            blocks << current_block unless current_block.empty?
            current_block = []
          else
            current_block << line
          end
        end
        blocks << current_block unless current_block.empty?

        worktrees = blocks.map { |block| Worktree.from_porcelain_block(block) }.compact
        new(worktrees)
      end

      def self.fetch(repo_path: nil)
        output = if repo_path
          `git -C #{repo_path.shellescape} worktree list --porcelain 2>/dev/null`
        else
          `git worktree list --porcelain 2>/dev/null`
        end
        from_porcelain(output)
      end

      attr_reader :worktrees

      def initialize(worktrees)
        @worktrees = worktrees
      end

      def each(&block)
        worktrees.each(&block)
      end

      def find_by_path(path)
        worktrees.find { |wt| wt.path == path }
      end

      def find_by_name(name)
        worktrees.find { |wt| wt.name == name }
      end

      def find_by_branch(branch)
        worktrees.find { |wt| wt.branch == branch }
      end

      def matching(pwd)
        worktrees.find { |wt| wt.match?(pwd) }
      end

      def without_bare
        self.class.new(worktrees.reject(&:bare?))
      end

      def detached
        self.class.new(worktrees.select(&:detached?))
      end

      def with_branch
        self.class.new(worktrees.reject(&:detached?))
      end

      def names
        worktrees.map(&:name)
      end

      def paths
        worktrees.map(&:path)
      end

      def empty?
        worktrees.empty?
      end

      def size
        worktrees.size
      end
      alias count size
      alias length size
    end
  end
end
