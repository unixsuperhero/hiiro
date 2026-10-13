class Hiiro
  # The `h tuios ui` TUI: one row per tuios window from a TuiosListing, a
  # detail pane with the pane's captured screen, and keys that run tuios verbs
  # through the listing's runner.
  class TuiosScreen < Tui::Screen
    KEY_HINT = '[enter]jump [/]search [c]apture [R]eload [H]osts [g]scope [n]ame [M]in [N]ew [m]ail [y]ank id [q]uit'.freeze
    LABEL_WIDTH = 18
    MARKS = { 'working' => '●', 'needs_input' => '?', 'done' => '✓', 'idle' => '○', 'errored' => '!' }.freeze
    CAPTURE_LINES = '20'.freeze

    key :enter, :jump
    key 'o', :jump
    key 'c', :capture
    key 'R', :reload
    key 'H', :toggle_hosts
    key 'g', :toggle_scope
    key 'n', :rename
    key 'M', :toggle_minimized
    key 'N', :new_window
    key 'm', :mail
    key 'y', :yank_id

    attr_reader :listing, :scope, :current, :runner, :own, :clipboard, :captures

    def initialize(listing:, scope: :global, current: nil, runner: nil, own: ENV.slice('TUIOS_SESSION', 'TUIOS_PANE_ID'),
                   clipboard: ->(text) { Hiiro::Shell.pipe(text, 'pbcopy') })
      @listing = listing
      @current = current
      @runner = runner || listing.runner
      @own = own
      @clipboard = clipboard
      @captures = {}
      @task_dirs = current ? task_dirs(current) : []
      @scope = scope == :task && task_rows.any? ? :task : :global
      super(items: [], empty_message: 'No windows.')
      rebuild!
    end

    def rebuild!(select: nil)
      key = select || current_item&.key
      @items = scope == :task ? task_rows : listing.windows
      index = key && filtered_items.index { |row| row.key == key }
      state.cursor = index if index
      move(0)
    end

    def row_text(row, width)
      head = "#{own_mark(row)}#{row.label.ljust(label_width)}  #{ws_cell(row)}  #{mark(row)} "
      return "#{head}(#{row.windows} windows)" if row.kind == :session

      suffix = row.minimized ? '  (min)' : ''
      tail = row.harness.to_s.empty? ? '' : "  #{row.harness}"
      title = truncate(row.title, [width - head.length - suffix.length - tail.length, 0].max)
      "#{head}#{title}#{suffix}#{tail}"
    end

    def format_row(row, current, line_cols) = super(row_text(row, line_cols - 2), current, line_cols)

    def max_horizontal_offset(line_cols = nil, visible = nil)
      line_cols ||= [terminal_cols - 1, 1].max
      super(line_cols, (visible || window_items).map { |row| row_text(row, line_cols - 2) })
    end

    def header_lines
      label = scope == :task ? "task(@#{current.name})" : 'global'
      counts = listing.attention.map { |kind, count| "#{count} #{kind}" }
      windows = items.count { |row| row.kind == :window }
      [
        "tuios  host:#{listing.hosts ? 'all' : 'local'}  scope:#{label}  #{windows} windows in #{listing.sessions.length} sessions  " \
        "attention: #{counts.empty? ? 'none' : counts.join(', ')}",
        KEY_HINT,
      ]
    end

    def detail_lines(row)
      if row.kind == :session
        return [field('host', row.host), field('session', row.session), field('windows', row.windows), field('state', row.state), '',
                field('attach', "tuios attach --host #{row.host} #{row.session}")]
      end

      lines = captures[row.id]
      [
        field('title', row.title), field('session', row.session), field('ws', row.workspace), field('state', row.state),
        field('harness', row.harness), field('message', row.message), field('cwd', row.cwd), field('cmd', row.cmd), field('id', row.id), '',
        *(lines ? ["screen (#{lines.length})", *lines] : [field('screen', '(press c)')]),
      ]
    end

    def match?(row, query)
      query = query.downcase
      texts = row.kind == :window ? [row.label, row.title, row.state, row.harness, row.cwd, row.id] : [row.label, row.state]
      texts.any? { |text| text.to_s.downcase.include?(query) }
    end

    private

    def field(label, value) = "#{label.ljust(8)} #{value.to_s.empty? ? '-' : value}"

    def mark(row) = MARKS.fetch(row.state.to_s, ' ')

    def ws_cell(row) = row.kind == :window ? "ws#{row.workspace}" : '-  '

    def own_mark(row) = row.kind == :window && row.session == own['TUIOS_SESSION'] ? '*' : ' '

    def label_width = [filtered_items.map { |row| row.label.length }.max || 0, LABEL_WIDTH].min

    def task_dirs(task)
      location = TaskLocation.for(task)
      [location.code_directory, location.worktree_path, location.home].compact.uniq
    end

    def task_rows
      listing.windows.select { |row| row.kind == :window && row.cwd && @task_dirs.any? { |dir| contains?(dir, row.cwd) } }
    end

    def contains?(dir, path)
      TaskLocation.contains?(dir, path)
    rescue Errno::ENOENT
      false
    end

    def window_row
      row = current_item
      if row.nil?
        self.message = 'no window'
      elsif row.kind == :session
        self.message = "remote session: tuios attach --host #{row.host} #{row.session}"
      else
        return row
      end
      nil
    end

    def attempt(success = nil)
      yield
      self.message = success if success
    rescue Hiiro::Error => e
      self.message = e.message
    end

    def reload_selecting(key)
      listing.reload
      rebuild!(select: key)
    end

    def jump
      row = window_row
      return unless row

      attempt do
        runner.call('jump-window', row.id)
        finish(true)
      end
    end

    def capture
      row = window_row
      return unless row

      attempt do
        text = runner.call('capture-pane', '-s', row.session, '-w', row.id, '--lines', CAPTURE_LINES)
        lines = text.dup.force_encoding(Encoding::UTF_8).scrub.lines.map(&:chomp)
        lines.pop while lines.any? && lines.last.strip.empty?
        captures[row.id] = lines
        self.message = "captured #{lines.length} lines"
      end
    end

    def reload
      attempt('reloaded') do
        listing.reload
        captures.clear
        rebuild!
      end
    end

    def toggle_hosts
      attempt do
        listing.hosts = !listing.hosts
        listing.reload
        captures.clear
        rebuild!
      end
    end

    def toggle_scope
      if task_rows.empty?
        self.message = 'no current task to scope to'
        return
      end

      @scope = scope == :task ? :global : :task
      rebuild!
    end

    def rename
      row = window_row
      return unless row

      prompt('name', default: row.title) do |text|
        attempt do
          runner.call('set-window', '-s', row.session, '-w', row.id, '--name', text)
          reload_selecting(row.id)
        end
      end
    end

    def toggle_minimized
      row = window_row
      return unless row

      attempt do
        runner.call('set-window', '-s', row.session, '-w', row.id, row.minimized ? '--restore' : '--minimize')
        reload_selecting(row.id)
      end
    end

    def new_window
      row = window_row
      return unless row

      prompt('new window') do |text|
        attempt do
          cwd = row.cwd ? ['--cwd', row.cwd] : []
          id = runner.call('new-window', text, '-s', row.session, *cwd, '--print-id', '--no-focus').strip
          reload_selecting(id)
          self.message = "opened #{id}"
        end
      end
    end

    def mail
      row = window_row
      return unless row

      from = own['TUIOS_PANE_ID'].to_s
      if from.empty?
        self.message = 'no own pane'
        return
      end

      prompt('message', complete: { '@' => -> { Completions.projects } }) do |text|
        attempt('sent') { runner.call('send-agent-message', text, '-s', row.session, '-w', row.id, '--from', from) }
      end
    end

    def yank_id
      row = window_row
      return unless row

      clipboard.call(row.id)
      self.message = "copied #{row.id}"
    end
  end
end
