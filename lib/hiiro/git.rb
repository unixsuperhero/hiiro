require_relative 'git/worktree'
require_relative 'git/worktrees'
require_relative 'git/branch'
require_relative 'git/branches'
require_relative 'git/remote'
require_relative 'git/pr'

class Hiiro
  class Git
    def self.add_resolvers(hiiro)
      hiiro.add_resolver(:branch, -> { hiiro.fuzzyfind(Branches.local.names) }) do |name|
        Branches.local.find_by_name(name)&.name || name
      end

      hiiro.add_resolver(:worktree,
        -> {
          wts = Worktrees.fetch.without_bare
          map = wts.each_with_object({}) { |wt, h| h["#{wt.name}  #{wt.path}"] = wt.path }
          hiiro.fuzzyfind_from_map(map)
        }
      ) do |ref|
        wts = Worktrees.fetch
        (wts.find_by_path(ref) || wts.find_by_name(ref) || wts.find_by_branch(ref))&.path || ref
      end
    end

    attr_reader :hiiro, :pwd

    def initialize(hiiro, pwd=Dir.pwd)
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

    def detached?
      current_branch_name == 'HEAD'
    end

    def commit(ref = 'HEAD', short: false)
      args = short ? ['rev-parse', '--short', ref] : ['rev-parse', ref]
      run_safe(*args)
    end

    # Branch convenience methods

    def branch
      current_branch_name
    end

    def branch_current
      run_safe('branch', '--show-current')
    end

    def current_branch
      Branch.current
    end

    def current_branch_name
      run_safe('rev-parse', '--abbrev-ref', 'HEAD')
    end

    def branches(sort_by: nil, ignore_case: false)
      Branches.fetch(sort_by: sort_by, ignore_case: ignore_case).names
    end

    def branches_collection(sort_by: nil, ignore_case: false)
      Branches.fetch(sort_by: sort_by, ignore_case: ignore_case)
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

    # Worktree convenience methods

    def worktrees(repo_path: nil)
      worktrees_collection(repo_path: repo_path).to_a
    end

    def worktrees_collection(repo_path: nil)
      Worktrees.fetch(repo_path: repo_path)
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

    def disable_sparse_checkout(path)
      run_system('-C', path, 'sparse-checkout', 'disable')
    end

    def sparse_checkout(path, dirs, cone: true)
      if cone
        run_system('-C', path, 'sparse-checkout', 'init', '--cone')
        dirs = dirs.map { |d| d.sub(%r{\A/}, '') }
      else
        run_system('-C', path, 'sparse-checkout', 'init')
      end
      run_system('-C', path, 'sparse-checkout', 'set', '--skip-checks', *dirs)
    end

    # Remote convenience methods

    def remotes
      Remote.all
    end

    def origin
      Remote.origin
    end

    def push(remote: 'origin', branch: nil, force: false)
      Remote.new(name: remote).push(branch, force: force)
    end

    def pull(remote: 'origin', branch: nil)
      Remote.new(name: remote).pull(branch)
    end

    def fetch_remote(remote: 'origin')
      Remote.new(name: remote).fetch_remote
    end

    # PR convenience methods

    def current_pr
      Pr.current
    end

    def list_prs(state: 'open', limit: 30)
      Pr.list(state: state, limit: limit)
    end

    def create_pr(title:, body: nil, base: nil, draft: false)
      Pr.create(title: title, body: body, base: base, draft: draft)
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
  end
end
