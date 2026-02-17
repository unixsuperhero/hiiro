class Hiiro
  class Tmux
    class Pane
      FORMAT = '#{pane_id}|#{pane_index}|#{pane_active}|#{pane_current_command}|#{pane_current_path}|#{pane_width}|#{pane_height}|#{window_id}|#{session_name}'

      attr_reader :id, :index, :command, :path, :width, :height, :window_id, :session_name

      def self.from_format_line(line)
        return nil if line.nil? || line.strip.empty?

        parts = line.strip.split('|', 9)
        return nil if parts.size < 7

        id, index, active, command, path, width, height, window_id, session_name = parts

        new(
          id: id,
          index: index.to_i,
          active: active == '1',
          command: command,
          path: path,
          width: width.to_i,
          height: height.to_i,
          window_id: window_id,
          session_name: session_name
        )
      end

      def self.current
        output = `tmux display-message -p '#{FORMAT}' 2>/dev/null`.strip
        return nil if output.empty?

        from_format_line(output)
      end

      def initialize(id:, index:, active: false, command: nil, path: nil, width: 0, height: 0, window_id: nil, session_name: nil)
        @id = id
        @index = index
        @active = active
        @command = command
        @path = path
        @width = width
        @height = height
        @window_id = window_id
        @session_name = session_name
      end

      def active?
        @active
      end

      def target
        id
      end

      def kill
        system('tmux', 'kill-pane', '-t', target)
      end

      def select
        system('tmux', 'select-pane', '-t', target)
      end

      def swap_with(other_target)
        system('tmux', 'swap-pane', '-s', target, '-t', other_target)
      end

      def move_to(dest_target)
        system('tmux', 'move-pane', '-s', target, '-t', dest_target)
      end

      def break_out(dest_window: nil)
        args = ['tmux', 'break-pane', '-s', target]
        args += ['-t', dest_window] if dest_window
        system(*args)
      end

      def join_to(dest_target, horizontal: false)
        args = ['tmux', 'join-pane', '-s', target, '-t', dest_target]
        args << '-h' if horizontal
        system(*args)
      end

      def resize(width: nil, height: nil)
        args = ['tmux', 'resize-pane', '-t', target]
        args += ['-x', width.to_s] if width
        args += ['-y', height.to_s] if height
        system(*args)
      end

      def zoom
        system('tmux', 'resize-pane', '-Z', '-t', target)
      end

      def capture(buffer: nil, start_line: nil, end_line: nil)
        args = ['tmux', 'capture-pane', '-t', target, '-p']
        args += ['-b', buffer] if buffer
        args += ['-S', start_line.to_s] if start_line
        args += ['-E', end_line.to_s] if end_line
        `#{args.shelljoin}`
      end

      def to_h
        {
          id: id,
          index: index,
          active: active?,
          command: command,
          path: path,
          width: width,
          height: height,
          window_id: window_id,
          session_name: session_name
        }.compact
      end

      def to_s
        "#{session_name}:#{window_id}.#{index} [#{command}] #{path}"
      end
    end
  end
end
