class Hiiro
  # Every directory you work in as one flat list: a row per git worktree under
  # the roots, a row per plain directory, and a row per alias from table `project`.
  class ProjectCatalog
    Repo = Struct.new(:name, :path, :trees, keyword_init: true)
    Tree = Struct.new(:path, :branch, :head, keyword_init: true)
    Row = Struct.new(:name, :path, :kind, :repo, :branch, :head, keyword_init: true) do
      def key = path
      def main? = kind == :tree && path == repo.path
    end

    # WORK_DIR is set after the requires, so the default is read at call time.
    def self.default_roots = [File.join(Dir.home, 'proj'), Hiiro::WORK_DIR]

    def self.load(roots: default_roots, aliases: {})
      new(roots:, aliases:)
    end

    attr_reader :roots, :aliases, :rows, :repos

    def initialize(roots:, aliases:)
      @roots = roots
      @aliases = aliases
      reload
    end

    def reload
      @repos = {}
      dirs = []
      roots.each do |root|
        next unless Dir.exist?(root)

        root = File.realpath(root)
        next add_repo(root, name: File.basename(root), path: root) if git_dir?(root)

        children(root).each { |child| dirs << child unless git_dir?(child) && add_repo(child) }
      end

      alias_rows = aliases.map { |name, path| Row.new(name: name.to_s, path: path.to_s, kind: :alias) }
      dir_rows = dirs.map { |path| Row.new(name: File.basename(path), path:, kind: :dir) }
      @rows = (repos.values.flat_map { |repo| tree_rows(repo) } + dir_rows + alias_rows).sort_by { |row| sort_key(row) }
      self
    end

    def repo_for(row) = row.repo

    private

    def git_dir?(path) = File.exist?(File.join(path, '.git'))

    def children(root)
      Dir.children(root).sort.map { |name| File.join(root, name) }.select { |path| File.directory?(path) }
    end

    # The same repo reached from two of its worktree directories is added once,
    # keyed by its main worktree (the root itself when the root is the repo).
    # Returns nil when git answers nothing, so the caller keeps a plain dir row.
    def add_repo(dir, name: nil, path: nil)
      worktrees = Git::Worktrees.fetch(repo_path: dir).without_bare.to_a
      return nil if worktrees.empty? && path.nil?

      main = path || worktrees.first.path
      return true if repos.key?(main)

      trees = worktrees.map { |wt| Tree.new(path: wt.path, branch: wt.branch || (wt.detached? ? '(detached)' : nil), head: wt.head&.slice(0, 7)) }
      repos[main] = Repo.new(name: name || File.basename(main), path: main, trees:)
    end

    def tree_rows(repo)
      repo.trees.map do |tree|
        name = tree.path == repo.path ? repo.name : "#{repo.name} ▸ #{relative_name(repo, tree.path)}"
        Row.new(name:, path: tree.path, kind: :tree, repo:, branch: tree.branch, head: tree.head)
      end
    end

    def relative_name(repo, path)
      [repo.path, File.dirname(repo.path)].each do |base|
        prefix = "#{base}/"
        return path.delete_prefix(prefix) if path.start_with?(prefix)
      end
      File.basename(path)
    end

    def sort_key(row)
      [row.repo ? row.repo.name : row.name, row.main? ? 0 : 1, row.path]
    end
  end
end
