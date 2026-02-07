class Hiiro
  class Git
    attr_reader :hiiro, :pwd

    def initialize(hiiro, pwd)
      @hiiro = hiiro
      @pwd = pwd
    end

    # Query methods

    def in_repo?
      !root.nil?
    end

    def root
      @root ||= run_safe('rev-parse', '--show-toplevel')
    end

    def branch
      run_safe('rev-parse', '--abbrev-ref', 'HEAD')
    end

    def branch_current
      run_safe('branch', '--show-current')
    end

    def detached?
      branch == 'HEAD'
    end

    def commit(ref = 'HEAD', short: false)
      args = short ? ['rev-parse', '--short', ref] : ['rev-parse', ref]
      run_safe(*args)
    end

    # Branch operations

    def branches(sort_by: nil, ignore_case: false)
      args = ['branch', '--format=%(refname:short)']
      args << '-i' if ignore_case
      args << "--sort=#{sort_by}" if sort_by

      result = run_safe(*args)
      return [] unless result

      result.split("\n").map(&:strip)
    end

    def branch_exists?(name)
      run_success?('show-ref', '--verify', '--quiet', "refs/heads/#{name}")
    end

    def create_branch(name, start_point = nil)
      args = ['checkout', '-b', name]
      args << start_point if start_point
      run_system(*args)
    end

    def checkout(ref)
      run_system('checkout', ref)
    end

    def delete_branch(name, force: false)
      flag = force ? '-D' : '-d'
      run_system('branch', flag, name)
    end

    # Worktree operations

    def worktrees(repo_path: nil)
      output = worktrees_porcelain(repo_path: repo_path)
      return [] unless output

      parse_worktrees(output)
    end

    def worktrees_porcelain(repo_path: nil)
      if repo_path
        run_safe('-C', repo_path, 'worktree', 'list', '--porcelain')
      else
        run_safe('worktree', 'list', '--porcelain')
      end
    end

    def add_worktree(path, branch: nil, detach: false)
      args = ['worktree', 'add']
      args << '--detach' if detach
      args << path
      args << branch if branch && !detach
      run_system(*args)
    end

    def add_worktree_detached(path, repo_path: nil)
      if repo_path
        run_system('-C', repo_path, 'worktree', 'add', '--detach', path)
      else
        run_system('worktree', 'add', '--detach', path)
      end
    end

    def move_worktree(from, to, repo_path: nil)
      if repo_path
        run_system('-C', repo_path, 'worktree', 'move', from, to)
      else
        run_system('worktree', 'move', from, to)
      end
    end

    def remove_worktree(path, force: false)
      args = ['worktree', 'remove']
      args << '--force' if force
      args << path
      run_system(*args)
    end

    def lock_worktree(path)
      run_system('worktree', 'lock', path)
    end

    def unlock_worktree(path)
      run_system('worktree', 'unlock', path)
    end

    def prune_worktrees
      run_system('worktree', 'prune')
    end

    def repair_worktrees
      run_system('worktree', 'repair')
    end

    # Remote operations

    def push(remote: 'origin', branch: nil)
      args = ['push', remote]
      args << branch if branch
      run_system(*args)
    end

    def pull(remote: 'origin', branch: nil)
      args = ['pull', remote]
      args << branch if branch
      run_system(*args)
    end

    private

    def run_safe(*args)
      result = `git #{args.shelljoin} 2>/dev/null`.strip
      result.empty? ? nil : result
    end

    def run_system(*args)
      system('git', *args)
    end

    def run_success?(*args)
      system('git', *args, out: File::NULL, err: File::NULL)
    end

    def parse_worktrees(output)
      trees = []
      current = {}

      output.each_line do |line|
        line = line.chomp
        if line.empty?
          trees << Worktree.new(current) if current[:path]
          current = {}
        elsif line.start_with?('worktree ')
          current[:path] = line.sub('worktree ', '')
        elsif line.start_with?('HEAD ')
          current[:head] = line.sub('HEAD ', '')
        elsif line.start_with?('branch ')
          current[:branch] = line.sub('branch ', '').sub('refs/heads/', '')
        elsif line == 'detached'
          current[:detached] = true
        elsif line == 'bare'
          current[:bare] = true
        end
      end

      trees << Worktree.new(current) if current[:path]
      trees
    end

    class Worktree
      attr_reader :path, :head, :branch

      def initialize(attrs = {})
        @path = attrs[:path]
        @head = attrs[:head]
        @branch = attrs[:branch]
        @detached = attrs[:detached] || false
        @bare = attrs[:bare] || false
      end

      def detached?
        @detached
      end

      def bare?
        @bare
      end

      def name
        File.basename(path)
      end
    end
  end
end
