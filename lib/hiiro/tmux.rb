require_relative 'tmux/session'
require_relative 'tmux/sessions'
require_relative 'tmux/window'
require_relative 'tmux/windows'
require_relative 'tmux/pane'
require_relative 'tmux/panes'
require_relative 'tmux/buffer'
require_relative 'tmux/buffers'

class Hiiro
  class Tmux
    def self.client!(hiiro = nil)
      @client = new(hiiro)
    end

    def self.client(hiiro = nil)
      return @client if @client && @client.hiiro == hiiro

      if hiiro
        client!(hiiro)
      else
        new
      end
    end

    def self.open_session(name)
      client.open_session(name)
    end

    attr_reader :hiiro

    def initialize(hiiro = nil)
      @hiiro = hiiro
    end

    # Context methods

    def in_tmux?
      !ENV['TMUX'].nil? && !ENV['TMUX'].empty?
    end

    def in_nvim?
      !ENV['NVIM'].nil? && !ENV['NVIM'].empty?
    end

    def server_running?
      run_success?('has-session')
    end

    def current_session
      Session.current
    end

    def current_window
      Window.current
    end

    def current_pane
      Pane.current
    end

    # Collection accessors

    def sessions
      Sessions.fetch
    end

    def windows(session: nil, all: false)
      Windows.fetch(session: session, all: all)
    end

    def panes(target: nil, all: false)
      Panes.fetch(target: target, all: all)
    end

    def buffers
      Buffers.fetch
    end

    # Session methods

    def session_exists?(name)
      run_success?('has-session', '-t', name)
    end

    def open_session(name)
      session_name = name.to_s

      unless session_exists?(session_name)
        run_system('new-session', '-d', '-A', '-s', session_name)
      end

      if in_tmux?
        switch_client(session_name)
      elsif in_nvim?
        puts "Can't attach to tmux inside a vim terminal"
        false
      else
        attach_session(session_name)
      end
    end

    def new_session(name = nil, **opts)
      args = ['new-session']
      args << '-d' if opts[:detached]
      args += ['-s', name] if name
      args += ['-c', opts[:start_directory]] if opts[:start_directory]
      args += ['-n', opts[:window_name]] if opts[:window_name]
      run_system(*args)
    end

    def kill_session(name)
      run_system('kill-session', '-t', name)
    end

    def attach_session(name)
      run_system('attach-session', '-t', name)
    end

    def switch_client(name)
      run_system('switch-client', '-t', name)
    end

    def detach_client(session: nil)
      args = ['detach-client']
      args += ['-s', session] if session
      run_system(*args)
    end

    def rename_session(old_name, new_name)
      run_system('rename-session', '-t', old_name, new_name)
    end

    # Window methods

    def new_window(name: nil, target: nil, start_directory: nil)
      args = ['new-window']
      args += ['-t', target] if target
      args += ['-n', name] if name
      args += ['-c', start_directory] if start_directory
      run_system(*args)
    end

    def kill_window(target)
      run_system('kill-window', '-t', target)
    end

    def select_window(target)
      run_system('select-window', '-t', target)
    end

    def next_window
      run_system('next-window')
    end

    def previous_window
      run_system('previous-window')
    end

    def last_window
      run_system('last-window')
    end

    def rename_window(target, new_name)
      run_system('rename-window', '-t', target, new_name)
    end

    def swap_window(src, dst)
      run_system('swap-window', '-s', src, '-t', dst)
    end

    def move_window(src, dst)
      run_system('move-window', '-s', src, '-t', dst)
    end

    def link_window(src, dst)
      run_system('link-window', '-s', src, '-t', dst)
    end

    def unlink_window(target)
      run_system('unlink-window', '-t', target)
    end

    # Pane methods

    def split_window(horizontal: false, target: nil, start_directory: nil)
      args = ['split-window']
      args << '-h' if horizontal
      args << '-v' unless horizontal
      args += ['-t', target] if target
      args += ['-c', start_directory] if start_directory
      run_system(*args)
    end

    def kill_pane(target)
      run_system('kill-pane', '-t', target)
    end

    def select_pane(target)
      run_system('select-pane', '-t', target)
    end

    def swap_pane(src, dst)
      run_system('swap-pane', '-s', src, '-t', dst)
    end

    def move_pane(src, dst)
      run_system('move-pane', '-s', src, '-t', dst)
    end

    def break_pane(src: nil, dst: nil)
      args = ['break-pane']
      args += ['-s', src] if src
      args += ['-t', dst] if dst
      run_system(*args)
    end

    def join_pane(src, dst, horizontal: false)
      args = ['join-pane', '-s', src, '-t', dst]
      args << '-h' if horizontal
      run_system(*args)
    end

    def resize_pane(target: nil, width: nil, height: nil, zoom: false)
      args = ['resize-pane']
      args += ['-t', target] if target
      args << '-Z' if zoom
      args += ['-x', width.to_s] if width
      args += ['-y', height.to_s] if height
      run_system(*args)
    end

    def capture_pane(target: nil, buffer: nil, print: true)
      args = ['capture-pane']
      args += ['-t', target] if target
      args += ['-b', buffer] if buffer
      args << '-p' if print
      if print
        run_safe(*args)
      else
        run_system(*args)
      end
    end

    # Buffer methods

    def set_buffer(content, name: nil)
      args = ['set-buffer']
      args += ['-b', name] if name
      args << content
      run_system(*args)
    end

    def load_buffer(path, name: nil)
      args = ['load-buffer']
      args += ['-b', name] if name
      args << path
      run_system(*args)
    end

    def save_buffer(path, name: nil)
      args = ['save-buffer']
      args += ['-b', name] if name
      args << path
      run_system(*args)
    end

    def paste_buffer(name: nil, target: nil)
      args = ['paste-buffer']
      args += ['-b', name] if name
      args += ['-t', target] if target
      run_system(*args)
    end

    def delete_buffer(name)
      run_system('delete-buffer', '-b', name)
    end

    def show_buffer(name)
      run_safe('show-buffer', '-b', name)
    end

    def choose_buffer
      run_system('choose-buffer')
    end

    # Display methods

    def display_message(message, target: nil)
      args = ['display-message']
      args += ['-t', target] if target
      args << message
      run_system(*args)
    end

    def display_info(format_string, target: nil)
      args = ['display-message', '-p']
      args += ['-t', target] if target
      args << format_string
      run_safe(*args)
    end

    private

    def run_safe(*args)
      output = `tmux #{args.shelljoin} 2>/dev/null`.strip
      output.empty? ? nil : output
    end

    def run_system(*args)
      system('tmux', *args)
    end

    def run_success?(*args)
      system('tmux', *args, out: File::NULL, err: File::NULL)
    end
  end
end
