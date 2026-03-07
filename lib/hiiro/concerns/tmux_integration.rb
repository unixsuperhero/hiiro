class Hiiro
  module TmuxIntegration
    # Ensure a tmux session exists, creating it if necessary.
    #
    # @param name [String] session name
    # @param working_dir [String] directory to start in (default: current dir)
    def ensure_session_exists(name, working_dir: Dir.pwd)
      return if session_exists?(name)
      system('tmux', 'new-session', '-d', '-s', name, '-c', working_dir)
    end

    # Check if a tmux session exists.
    #
    # @param name [String] session name
    # @return [Boolean] true if session exists
    def session_exists?(name)
      system('tmux', 'has-session', '-t', name, out: File::NULL, err: File::NULL)
    end

    # Get the current tmux session name.
    #
    # @return [String, nil] session name or nil if not in tmux
    def current_session_name
      return nil unless ENV['TMUX']
      `tmux display-message -p '#S'`.chomp
    end

    # Check if a tmux pane exists and is alive.
    #
    # @param pane_id [String] pane identifier
    # @return [Boolean] true if pane exists
    def pane_exists?(pane_id)
      return false unless pane_id
      system('tmux', 'has-session', '-t', pane_id, [:out, :err] => '/dev/null')
    end

    # Create a new tmux window in a session.
    #
    # @param session [String] session name
    # @param window_name [String] name for the new window
    # @param working_dir [String] directory to start in (optional)
    # @return [Array<String>] [window_target, pane_id]
    def create_tmux_window(session, window_name, working_dir: nil)
      cmd = ['tmux', 'new-window', '-d', '-t', session, '-n', window_name, '-P', "-F", '#{pane_id}']
      cmd += ['-c', working_dir] if working_dir
      pane_id = `#{cmd.join(' ')}`.chomp
      window_target = "#{session}:#{window_name}"
      [window_target, pane_id]
    end

    # Split an existing tmux pane vertically.
    #
    # @param window_target [String] window to adjust layout
    # @param target_pane_id [String] pane to split
    # @return [String] new pane id
    def split_tmux_pane(window_target, target_pane_id)
      pane_id = `tmux split-window -d -t #{target_pane_id} -P -F '\\#{pane_id}'`.chomp
      system('tmux', 'select-layout', '-t', window_target, 'even-vertical')
      pane_id
    end

    # Send keys to a tmux pane.
    #
    # @param pane_id [String] target pane
    # @param command [String] command to send
    def send_to_pane(pane_id, command)
      system('tmux', 'send-keys', '-t', pane_id, command, 'Enter')
    end

    # Switch to a specific tmux session/window/pane.
    #
    # @param session [String, nil] session name
    # @param window [String, nil] window name or target
    # @param pane [String, nil] pane id
    def switch_to_tmux_target(session: nil, window: nil, pane: nil)
      system('tmux', 'switch-client', '-t', session) if session
      system('tmux', 'select-window', '-t', window) if window
      system('tmux', 'select-pane', '-t', pane) if pane
    end
  end
end
