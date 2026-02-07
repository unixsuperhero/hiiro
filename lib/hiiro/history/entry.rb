class Hiiro
  class History
    class Entry
      FIELDS = %i[
        id timestamp source cmd description pwd
        tmux_session tmux_window tmux_pane
        git_branch git_sha git_origin_sha git_worktree
        task subtask app
      ].freeze

      attr_reader(*FIELDS)

      def initialize(data)
        data ||= {}
        @id = data['id']
        @timestamp = data['timestamp']
        @source = data['source']
        @cmd = data['cmd']
        @description = data['description']
        @pwd = data['pwd']
        @tmux_session = data['tmux_session']
        @tmux_window = data['tmux_window']
        @tmux_pane = data['tmux_pane']
        @git_branch = data['git_branch']
        @git_sha = data['git_sha']
        @git_origin_sha = data['git_origin_sha']
        @git_worktree = data['git_worktree']
        @task = data['task']
        @subtask = data['subtask']
        @app = data['app']
      end

      def to_h
        {
          'id' => id,
          'timestamp' => timestamp,
          'source' => source,
          'cmd' => cmd,
          'description' => description,
          'pwd' => pwd,
          'tmux_session' => tmux_session,
          'tmux_window' => tmux_window,
          'tmux_pane' => tmux_pane,
          'git_branch' => git_branch,
          'git_sha' => git_sha,
          'git_origin_sha' => git_origin_sha,
          'git_worktree' => git_worktree,
          'task' => task,
          'subtask' => subtask,
          'app' => app,
        }.compact
      end

      # Data used for change detection (excludes timestamp, id, cmd)
      def state_key
        {
          'pwd' => pwd,
          'tmux_session' => tmux_session,
          'tmux_window' => tmux_window,
          'tmux_pane' => tmux_pane,
          'git_branch' => git_branch,
          'git_sha' => git_sha,
          'git_origin_sha' => git_origin_sha,
          'git_worktree' => git_worktree,
          'task' => task,
          'subtask' => subtask,
          'app' => app,
        }.compact
      end

      def state_fingerprint
        Digest::SHA256.hexdigest(state_key.to_yaml)[0..15]
      end

      def short_line(index)
        time_str = timestamp ? Time.parse(timestamp).strftime('%Y-%m-%d %H:%M') : Time.now.strftime('%Y-%m-%d %H:%M')
        desc = description || cmd || '(no description)'
        desc = desc[0..50] + '...' if desc.length > 53
        [
          format('%3d  %s  %s', index, time_str, desc),
          format('     %s @ %s', git_branch || '(no branch)', task || '(no task)'),
        ].join("\n")
      end

      def oneline(index = nil)
        time_str = timestamp ? Time.parse(timestamp).strftime('%m/%d %H:%M') : ''
        prefix = index ? format('%3d  ', index) : ''
        branch_str = git_branch ? "[#{git_branch}]" : ''
        task_str = task ? "(#{task})" : ''
        cmd_str = cmd || description || ''
        cmd_str = cmd_str[0..40] + '...' if cmd_str.length > 43

        "#{prefix}#{time_str}  #{branch_str.ljust(20)}  #{task_str.ljust(15)}  #{cmd_str}"
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
        lines << "  Worktree:  #{git_worktree}" if git_worktree
        lines << "  Branch:    #{git_branch}" if git_branch
        lines << "  SHA:       #{git_sha}" if git_sha
        lines << "  Origin:    #{git_origin_sha}" if git_origin_sha
        lines << ""
        lines << "Task:"
        lines << "  Task:      #{task}" if task
        lines << "  Subtask:   #{subtask}" if subtask
        lines << "  App:       #{app}" if app
        lines.join("\n")
      end

      # Filter matching
      def matches?(filters)
        filters.all? do |key, value|
          entry_value = send(key) rescue nil
          next true if value.nil?
          next entry_value == value if value.is_a?(String)
          next value.include?(entry_value) if value.is_a?(Array)
          true
        end
      end
    end
  end
end
