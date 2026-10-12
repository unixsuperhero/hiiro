require 'json'
require 'open3'

class Hiiro
  # The `h project ui` TUI: one row per worktree, plain dir, or alias from a
  # ProjectCatalog, a detail pane, per-row facts fetched on a key, and worktree
  # add/remove through git.
  class ProjectScreen < Tui::Screen
    KEY_HINT = '[enter]open [/]search [g]scope [s]tatus [b]ranches [p]rs [a]dd tree [d]rop tree [y]ank path [q]uit'.freeze
    NAME_WIDTH = 28

    class Facts
      attr_reader :status, :branches, :prs

      def initialize
        @status = {}
        @branches = {}
        @prs = {}
      end
    end

    class Fetcher
      def status(path)
        lines = git(path, 'status', '--porcelain', '-b').lines.map(&:chomp)
        header = lines.shift.to_s
        { dirty: lines.length, ahead: header[/ahead (\d+)/, 1].to_i, behind: header[/behind (\d+)/, 1].to_i }
      end

      def branches(repo_path)
        git(repo_path, 'branch', '--format=%(refname:short)').lines.map(&:strip).reject(&:empty?)
      end

      def prs(repo_path)
        out = capture(%w[gh pr list --state open --limit 30 --json number,title,state], chdir: repo_path)
        JSON.parse(out).map { |pr| { number: pr['number'], state: pr['state'], title: pr['title'] } }
      end

      private

      def git(path, *args) = capture(['git', '-C', path, *args])

      def capture(argv, **opts)
        out, err, status = Open3.capture3(*argv, **opts)
        raise Hiiro::Error, err.lines.first.to_s.strip unless status.success?

        out
      rescue Errno::ENOENT => e
        raise Hiiro::Error, e.message
      end
    end

    # tuios when the pane runs in tuios, otherwise Herdr: the same call
    # `h project open` makes.
    class Opener
      def command(row)
        return nil unless ENV['TUIOS_ENV'] == '1'

        ['tuios', 'new-window', name_for(row), '-s', ENV['TUIOS_SESSION'].to_s, '--cwd', row.path]
      end

      def open(row)
        argv = command(row)
        return Hiiro::Herdr.open_workspace(name_for(row), start_directory: row.path) unless argv

        raise Hiiro::Error, 'tuios new-window failed' unless system(*argv)
      end

      def name_for(row) = row.name.tr('.', '_').tr(' ', '_').delete('▸').squeeze('_')
    end

    key :enter, :open_row
    key 'o', :open_row
    key 'g', :toggle_scope
    key 's', :fetch_status
    key 'b', :fetch_branches
    key 'p', :fetch_prs
    key 'a', :add_tree
    key 'd', :drop_tree
    key 'y', :yank_path

    attr_reader :catalog, :scope, :current, :facts, :opener, :fetcher, :clipboard

    def initialize(catalog:, scope: :global, current: nil, facts: Facts.new, opener: Opener.new, fetcher: Fetcher.new,
                   clipboard: ->(text) { Hiiro::Shell.pipe(text, 'pbcopy') })
      @catalog = catalog
      @current = current
      @facts = facts
      @opener = opener
      @fetcher = fetcher
      @clipboard = clipboard
      @current_tree = current && TaskLocation.for(current).worktree_path
      @current_tree = File.realpath(@current_tree) if @current_tree && Dir.exist?(@current_tree)
      @scope = scope == :task && current_row ? :task : :global
      super(items: [], empty_message: 'No projects.')
      rebuild!(select: @scope == :task ? current_row.key : nil)
    end

    # Re-reads the roots, then rebuilds the rows.
    def reload!(select: nil)
      catalog.reload
      rebuild!(select:)
    end

    # Rebuilds rows for the scope, keeping the cursor on the same path.
    def rebuild!(select: nil)
      key = select || current_item&.key
      @items = scoped_rows
      index = key && filtered_items.index { |row| row.key == key }
      state.cursor = index if index
      move(0)
    end

    def row_text(row)
      [row.name.ljust(name_width), branch_cell(row), row.head].reject { |part| part.to_s.empty? }.join('  ')
    end

    def format_row(row, current, line_cols) = super(row_text(row), current, line_cols)

    def max_horizontal_offset(line_cols = nil, visible = nil)
      super(line_cols, (visible || window_items).map { |row| row_text(row) })
    end

    def header_lines
      label = scope == :task ? "task(@#{current.name})" : 'global'
      ["projects  scope:#{label}  #{items.length} rows", KEY_HINT]
    end

    def detail_lines(row)
      return [field('name', row.name), field('path', row.path), field('kind', row.kind)] unless row.kind == :tree

      repo = row.repo
      [
        field('name', row.name),
        field('path', row.path),
        field('repo', repo.name),
        field('branch', row.branch),
        field('head', row.head),
        "worktrees (#{repo.trees.length})",
        *repo.trees.map { |tree| "  #{File.basename(tree.path)}  #{tree.branch}" },
        field('status', status_text(facts.status[row.path])),
        *listed('branches', facts.branches[repo.path]) { |name| "  #{name}" },
        *listed('prs', facts.prs[repo.path]) { |pr| "  ##{pr[:number]}  #{pr[:state]}  #{pr[:title]}" },
      ]
    end

    def match?(row, query)
      query = query.downcase
      [row.name, row.branch, row.path].any? { |text| text.to_s.downcase.include?(query) }
    end

    private

    def field(label, value) = "#{label.ljust(8)} #{value.to_s.empty? ? '-' : value}"

    def listed(label, values)
      return [field(label, nil)] unless values

      ["#{label} (#{values.length})", *values.map { |value| yield value }]
    end

    def name_width = [filtered_items.map { |row| row.name.length }.max || 0, NAME_WIDTH].min

    def branch_cell(row)
      return '-' unless row.kind == :tree

      [row.branch, *status_parts(facts.status[row.path])].join(' ')
    end

    def status_parts(status)
      return [] unless status

      [['*', status[:dirty]], ['↑', status[:ahead]], ['↓', status[:behind]]]
        .select { |_, count| count.to_i.positive? }.map { |mark, count| "#{mark}#{count}" }
    end

    def status_text(status)
      return nil unless status

      parts = status_parts(status)
      parts.empty? ? 'clean' : parts.join(' ')
    end

    def current_row
      @current_tree && catalog.rows.find { |row| row.kind == :tree && row.path == @current_tree }
    end

    def scoped_rows
      return catalog.rows unless scope == :task

      repo_path = current_row.repo.path
      catalog.rows.select { |row| row.kind == :tree && row.repo.path == repo_path }
    end

    def tree_row
      row = current_item
      return row if row&.kind == :tree

      self.message = 'not a git worktree'
      nil
    end

    def attempt(success = nil)
      yield
      self.message = success if success
    rescue Hiiro::Error => e
      self.message = e.message
    end

    def git(repo_path, *args)
      _out, err, status = Open3.capture3('git', '-C', repo_path, *args)
      raise Hiiro::Error, err.lines.first.to_s.strip unless status.success?
    end

    def branch_exists?(repo, branch)
      system('git', '-C', repo.path, 'show-ref', '--verify', '--quiet', "refs/heads/#{branch}")
    end

    def open_row
      row = current_item
      return unless row

      opener.open(row)
      finish(true)
    rescue Hiiro::Error => e
      self.message = e.message
    end

    def toggle_scope
      unless current_row
        self.message = 'no current task to scope to'
        return
      end

      @scope = scope == :task ? :global : :task
      rebuild!(select: scope == :task ? current_row.key : nil)
    end

    def fetch_status
      row = tree_row
      return unless row

      attempt { facts.status[row.path] = fetcher.status(row.path) }
      rebuild!
    end

    def fetch_branches
      row = tree_row
      return unless row

      attempt { facts.branches[row.repo.path] = fetcher.branches(row.repo.path) }
      rebuild!
    end

    def fetch_prs
      row = tree_row
      return unless row

      attempt { facts.prs[row.repo.path] = fetcher.prs(row.repo.path) }
      rebuild!
    end

    def add_tree
      row = tree_row
      return unless row

      repo = row.repo
      prompt('branch') do |branch|
        branch = branch.strip
        next if branch.empty?

        prompt('path', default: File.join(File.dirname(repo.path), File.basename(branch))) do |path|
          path = path.strip
          next if path.empty?

          args = branch_exists?(repo, branch) ? ['worktree', 'add', path, branch] : ['worktree', 'add', path, '-b', branch]
          attempt("added #{path}") do
            git(repo.path, *args)
            reload!(select: path)
          end
        end
      end
    end

    def drop_tree
      row = current_item
      return unless row

      unless row.kind == :tree && !row.main?
        self.message = 'not a removable worktree'
        return
      end

      prompt("remove #{row.path}? (y/n)") do |answer|
        next unless answer == 'y'

        attempt("removed #{row.path}") do
          git(row.repo.path, 'worktree', 'remove', row.path)
          reload!
        end
      end
    end

    def yank_path
      row = current_item
      return unless row

      clipboard.call(row.path)
      self.message = "copied #{row.path}"
    end
  end
end
