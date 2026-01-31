require 'yaml'
require 'time'
require 'fileutils'

class Hiiro
  class History
    HISTORY_FILE = File.join(Dir.home, '.config/hiiro/history.yml')

    class Entry
      attr_reader :id, :timestamp, :source, :cmd, :description
      attr_reader :tmux_session, :tmux_window, :tmux_pane
      attr_reader :git_branch, :git_worktree
      attr_reader :task, :subtask

      def initialize(data)
        data ||= {}
        @id = data['id']
        @timestamp = data['timestamp']
        @source = data['source']
        @cmd = data['cmd']
        @description = data['description']
        @tmux_session = data['tmux_session']
        @tmux_window = data['tmux_window']
        @tmux_pane = data['tmux_pane']
        @git_branch = data['git_branch']
        @git_worktree = data['git_worktree']
        @task = data['task']
        @subtask = data['subtask']
      end

      def to_h
        {
          'id' => id,
          'timestamp' => timestamp,
          'source' => source,
          'cmd' => cmd,
          'description' => description,
          'tmux_session' => tmux_session,
          'tmux_window' => tmux_window,
          'tmux_pane' => tmux_pane,
          'git_branch' => git_branch,
          'git_worktree' => git_worktree,
          'task' => task,
          'subtask' => subtask,
        }.compact
      end

      def short_line(index)
        time_str = timestamp ? Time.parse(timestamp).strftime('%Y-%m-%d %H:%M') : Time.now.iso8601
        desc = description || cmd || '(no description)'
        desc = desc[0..60] + '...' if desc.length > 63
        [
          format('%3d  %s  %s', index, time_str, desc),
          format('   cmd: %s', cmd),
        ].join("\n")
      end

      def full_display
        lines = []
        lines << "ID:          #{id}"
        lines << "Timestamp:   #{timestamp}"
        lines << "Description: #{description}" if description
        lines << "Command:     #{cmd}" if cmd
        lines << "PWD:         #{pwd}" if pwd
        lines << "Source:      #{source}" if source
        lines << ""
        lines << "Tmux:"
        lines << "  Session:   #{tmux_session}" if tmux_session
        lines << "  Window:    #{tmux_window}" if tmux_window
        lines << "  Pane:      #{tmux_pane}" if tmux_pane
        lines << ""
        lines << "Git:"
        lines << "  Branch:    #{git_branch}" if git_branch
        lines << "  Worktree:  #{git_worktree}" if git_worktree
        lines << ""
        lines << "Task:"
        lines << "  Task:      #{task}" if task
        lines << "  Subtask:   #{subtask}" if subtask
        lines.join("\n")
      end
    end

    class << self
      def load(hiiro)
        history = new

        hiiro.add_subcmd(:history) do |*args|
          subcmd, *rest = args
          case subcmd
          when 'ls', 'list', nil
            history.list
          when 'show'
            history.show(rest.first)
          when 'goto'
            history.goto(rest.first)
          when 'add'
            history.add_manual(rest.join(' '), hiiro: hiiro)
          else
            puts "Unknown history subcommand: #{subcmd}"
            puts "Available: ls, show <id>, goto <id>, add <description>"
            false
          end
        end
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
    end

    def initialize
      ensure_history_file
    end

    def entries
      @entries ||= load_entries
    end

    def reload
      @entries = nil
      entries
    end

    def list
      if entries.empty?
        puts "No history entries."
        return true
      end

      entries.each_with_index do |entry, idx|
        puts entry.short_line(idx + 1)
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
        cmd: hiiro.full_command,
      )
      true
    end

    def add(description: nil, cmd: nil, source: nil, task: nil, subtask: nil, pwd: Dir.pwd)
      entry_data = {
        'id' => generate_id,
        'timestamp' => Time.now.iso8601,
        'description' => description,
        'cmd' => cmd,
        'pwd' => pwd,
        'source' => source,
        'tmux_session' => current_tmux_session,
        'tmux_window' => current_tmux_window,
        'tmux_pane' => current_tmux_pane,
        'git_branch' => current_git_branch,
        'git_worktree' => current_git_worktree,
        'task' => task,
        'subtask' => subtask,
      }.compact

      all = load_raw_entries
      all << entry_data
      save_entries(all)

      Entry.new(entry_data)
    end

    private

    def find_entry(ref)
      return nil unless ref

      if ref.to_s.match?(/^\d+$/)
        idx = ref.to_i - 1
        return entries[idx] if idx >= 0 && idx < entries.length
      end

      entries.find { |e| e.id == ref.to_s }
    end

    def generate_id
      Time.now.strftime('%Y%m%d%H%M%S') + '-' + rand(10000).to_s.rjust(4, '0')
    end

    def ensure_history_file
      dir = File.dirname(HISTORY_FILE)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

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
      File.write(HISTORY_FILE, entries_data.to_yaml)
    end

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
      `tmux display-message -p '#P'`.strip rescue nil
    end

    def current_git_branch
      branch = `git branch --show-current 2>/dev/null`.strip
      branch.empty? ? nil : branch
    rescue
      nil
    end

    def current_git_worktree
      worktree = `git rev-parse --show-toplevel 2>/dev/null`.strip
      worktree.empty? ? nil : worktree
    rescue
      nil
    end
  end
end
