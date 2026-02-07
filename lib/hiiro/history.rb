require 'yaml'
require 'time'
require 'fileutils'
require 'digest'
require_relative 'history/entry'

class Hiiro
  class History
    HISTORY_DIR = File.join(Dir.home, '.config/hiiro/history')
    HISTORY_FILE = File.join(HISTORY_DIR, 'entries.yml')
    LAST_STATE_FILE = File.join(HISTORY_DIR, 'last_state.yml')

    class << self
      def load(hiiro)
        history = new

        hiiro.add_subcmd(:history) do |*args|
          subcmd, *rest = args
          case subcmd
          when 'ls', 'list', nil
            history.list(limit: 20)
          when 'all'
            history.list(limit: nil)
          when 'show'
            history.show(rest.first)
          when 'goto'
            history.goto(rest.first)
          when 'add'
            history.add_manual(rest.join(' '), hiiro: hiiro)
          when 'by'
            # h history by pane|window|session|task|branch [value]
            dimension, value = rest
            history.list_by(dimension, value)
          when 'clear'
            history.clear!
            puts "History cleared."
          else
            puts "Unknown history subcommand: #{subcmd}"
            puts "Available: ls, all, show <id>, goto <id>, add <description>, by <dimension> [value], clear"
            false
          end
        end
      end

      # Called automatically when a command runs (if in a task context)
      def track(cmd:, hiiro: nil)
        new.track_command(cmd: cmd, hiiro: hiiro)
      end

      def log(description: nil, pwd: Dir.pwd, cmd: nil, source: nil, task: nil, subtask: nil)
        new.add(
          description: description,
          cmd: cmd,
          pwd: pwd,
          source: source,
          task: task,
          subtask: subtask
        )
      end

      # Query helpers for other commands (e.g., h pane history)
      def by_pane(pane_id = nil)
        pane_id ||= current_tmux_pane
        new.filter(tmux_pane: pane_id)
      end

      def by_window(window_id = nil)
        window_id ||= current_tmux_window
        new.filter(tmux_window: window_id)
      end

      def by_session(session_name = nil)
        session_name ||= current_tmux_session
        new.filter(tmux_session: session_name)
      end

      def by_task(task_name)
        new.filter(task: task_name)
      end

      def by_branch(branch_name)
        new.filter(git_branch: branch_name)
      end

      def by_worktree(worktree_path)
        new.filter(git_worktree: worktree_path)
      end

      def by_app(app_name)
        new.filter(app: app_name)
      end

      private

      def current_tmux_pane
        return nil unless ENV['TMUX']
        `tmux display-message -p '#D'`.strip rescue nil
      end

      def current_tmux_window
        return nil unless ENV['TMUX']
        `tmux display-message -p '#S:#I'`.strip rescue nil
      end

      def current_tmux_session
        return nil unless ENV['TMUX']
        `tmux display-message -p '#S'`.strip rescue nil
      end
    end

    def initialize
      ensure_history_dir
    end

    def entries
      @entries ||= load_entries
    end

    def reload
      @entries = nil
      entries
    end

    def filter(filters = {})
      entries.select { |e| e.matches?(filters) }
    end

    def list(limit: 20)
      items = entries.reverse
      items = items.first(limit) if limit

      if items.empty?
        puts "No history entries."
        return true
      end

      items.reverse.each_with_index do |entry, idx|
        puts entry.oneline(idx + 1)
      end
      true
    end

    def list_by(dimension, value = nil)
      dimension_map = {
        'pane' => :tmux_pane,
        'window' => :tmux_window,
        'session' => :tmux_session,
        'task' => :task,
        'subtask' => :subtask,
        'branch' => :git_branch,
        'worktree' => :git_worktree,
        'app' => :app,
      }

      field = dimension_map[dimension]
      unless field
        puts "Unknown dimension: #{dimension}"
        puts "Available: #{dimension_map.keys.join(', ')}"
        return false
      end

      # If no value specified, use current context
      value ||= current_value_for(field)

      if value.nil?
        puts "No current #{dimension} detected. Please specify a value."
        return false
      end

      filtered = filter(field => value)

      if filtered.empty?
        puts "No history for #{dimension}=#{value}"
        return true
      end

      puts "History for #{dimension}: #{value}"
      puts
      filtered.last(20).each_with_index do |entry, idx|
        puts entry.oneline(idx + 1)
      end
      true
    end

    def show(ref)
      entry = find_entry(ref)
      unless entry
        puts "Entry not found: #{ref}"
        return false
      end

      puts entry.full_display
      true
    end

    def goto(ref)
      entry = find_entry(ref)
      unless entry
        puts "Entry not found: #{ref}"
        return false
      end

      unless entry.tmux_session
        puts "No tmux session recorded for this entry"
        return false
      end

      target = entry.tmux_session
      target += ":#{entry.tmux_window}" if entry.tmux_window
      target += ".#{entry.tmux_pane}" if entry.tmux_pane

      system('tmux', 'switch-client', '-t', target)
    end

    def add_manual(description, hiiro: nil)
      add(
        description: description,
        source: 'manual',
        cmd: hiiro&.full_command,
      )
      true
    end

    # Main tracking method - gathers all context and saves if changed
    def track_command(cmd:, hiiro: nil, force: false)
      context = gather_context
      return nil unless context[:task] || force # Only track if in a task context (unless forced)

      context[:cmd] = cmd
      context[:source] = 'auto'

      # Check if state changed
      unless force
        new_state = build_state_key(context)
        return nil if state_unchanged?(new_state)
        save_last_state(new_state)
      end

      add(**context)
    end

    def add(
      description: nil, cmd: nil, source: nil, pwd: nil,
      tmux_session: nil, tmux_window: nil, tmux_pane: nil,
      git_branch: nil, git_sha: nil, git_origin_sha: nil, git_worktree: nil,
      task: nil, subtask: nil, app: nil
    )
      context = gather_context

      entry_data = {
        'id' => generate_id,
        'timestamp' => Time.now.iso8601,
        'description' => description,
        'cmd' => cmd,
        'pwd' => pwd || context[:pwd],
        'source' => source,
        'tmux_session' => tmux_session || context[:tmux_session],
        'tmux_window' => tmux_window || context[:tmux_window],
        'tmux_pane' => tmux_pane || context[:tmux_pane],
        'git_branch' => git_branch || context[:git_branch],
        'git_sha' => git_sha || context[:git_sha],
        'git_origin_sha' => git_origin_sha || context[:git_origin_sha],
        'git_worktree' => git_worktree || context[:git_worktree],
        'task' => task || context[:task],
        'subtask' => subtask || context[:subtask],
        'app' => app || context[:app],
      }.compact

      all = load_raw_entries
      all << entry_data
      save_entries(all)

      Entry.new(entry_data)
    end

    def clear!
      save_entries([])
      File.delete(LAST_STATE_FILE) if File.exist?(LAST_STATE_FILE)
      @entries = nil
    end

    private

    def gather_context
      {
        pwd: Dir.pwd,
        tmux_session: current_tmux_session,
        tmux_window: current_tmux_window,
        tmux_pane: current_tmux_pane,
        git_branch: current_git_branch,
        git_sha: current_git_sha,
        git_origin_sha: current_git_origin_sha,
        git_worktree: current_git_worktree,
        task: current_task_name,
        subtask: current_subtask_name,
        app: current_app_name,
      }
    end

    def build_state_key(context)
      context.slice(
        :pwd, :tmux_session, :tmux_window, :tmux_pane,
        :git_branch, :git_sha, :git_origin_sha, :git_worktree,
        :task, :subtask, :app
      ).compact
    end

    def state_unchanged?(new_state)
      return false unless File.exist?(LAST_STATE_FILE)
      last_state = YAML.load_file(LAST_STATE_FILE) rescue {}
      last_state == new_state.transform_keys(&:to_s)
    end

    def save_last_state(state)
      File.write(LAST_STATE_FILE, state.transform_keys(&:to_s).to_yaml)
    end

    def current_value_for(field)
      context = gather_context
      context[field]
    end

    def find_entry(ref)
      return nil unless ref

      if ref.to_s.match?(/^\d+$/)
        idx = ref.to_i - 1
        reversed = entries.reverse
        return reversed[idx] if idx >= 0 && idx < reversed.length
      end

      entries.find { |e| e.id == ref.to_s }
    end

    def generate_id
      Time.now.strftime('%Y%m%d%H%M%S') + '-' + rand(10000).to_s.rjust(4, '0')
    end

    def ensure_history_dir
      FileUtils.mkdir_p(HISTORY_DIR) unless Dir.exist?(HISTORY_DIR)

      unless File.exist?(HISTORY_FILE)
        File.write(HISTORY_FILE, [].to_yaml)
      end
    end

    def load_raw_entries
      YAML.load_file(HISTORY_FILE) || []
    rescue => e
      []
    end

    def load_entries
      load_raw_entries.map { |data| Entry.new(data) }
    end

    def save_entries(entries_data)
      # Keep only last 1000 entries to prevent unbounded growth
      entries_data = entries_data.last(1000) if entries_data.length > 1000
      File.write(HISTORY_FILE, entries_data.to_yaml)
    end

    # Tmux context
    def current_tmux_session
      return nil unless ENV['TMUX']
      `tmux display-message -p '#S'`.strip rescue nil
    end

    def current_tmux_window
      return nil unless ENV['TMUX']
      `tmux display-message -p '#I'`.strip rescue nil
    end

    def current_tmux_pane
      return nil unless ENV['TMUX']
      ENV['TMUX_PANE'] || `tmux display-message -p '#P'`.strip rescue nil
    end

    # Git context
    def current_git_branch
      git_helper.branch_current
    end

    def current_git_sha
      git_helper.commit('HEAD', short: true)
    end

    def current_git_origin_sha
      branch = current_git_branch
      return nil unless branch
      git_helper.commit("origin/#{branch}", short: true)
    end

    def current_git_worktree
      git_helper.root
    end

    def git_helper
      @git_helper ||= Git.new(nil, Dir.pwd)
    end

    # Task context
    def current_task_name
      env = environment
      return nil unless env

      task = env.task
      return nil unless task

      task.subtask? ? task.parent_name : task.name
    end

    def current_subtask_name
      env = environment
      return nil unless env

      task = env.task
      return nil unless task
      return nil unless task.subtask?

      task.short_name
    end

    def current_app_name
      env = environment
      return nil unless env

      pwd = Dir.pwd
      task = env.task
      return nil unless task

      tree = env.find_tree(task.tree_name)
      return nil unless tree

      # Check if pwd is in an app directory
      env.all_apps.each do |app|
        app_path = app.resolve(tree.path)
        if pwd == app_path || pwd.start_with?(app_path + '/')
          return app.name
        end
      end

      nil
    end

    def environment
      @environment ||= begin
        Environment.current
      rescue NameError
        nil
      end
    end
  end
end
