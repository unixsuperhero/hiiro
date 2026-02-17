class Hiiro
  class Tmux
    class Window
      FORMAT = '#{window_id}|#{window_index}|#{window_name}|#{window_active}|#{window_panes}|#{session_name}'

      attr_reader :id, :index, :name, :panes, :session_name

      def self.from_format_line(line)
        return nil if line.nil? || line.strip.empty?

        parts = line.strip.split('|', 6)
        return nil if parts.size < 5

        id, index, name, active, panes, session_name = parts

        new(
          id: id,
          index: index.to_i,
          name: name,
          active: active == '1',
          panes: panes.to_i,
          session_name: session_name
        )
      end

      def self.current
        output = `tmux display-message -p '#{FORMAT}' 2>/dev/null`.strip
        return nil if output.empty?

        from_format_line(output)
      end

      def initialize(id:, index:, name:, active: false, panes: 1, session_name: nil)
        @id = id
        @index = index
        @name = name
        @active = active
        @panes = panes
        @session_name = session_name
      end

      def active?
        @active
      end

      def target
        "#{session_name}:#{index}"
      end

      def kill
        system('tmux', 'kill-window', '-t', target)
      end

      def rename(new_name)
        system('tmux', 'rename-window', '-t', target, new_name)
      end

      def select
        system('tmux', 'select-window', '-t', target)
      end

      def swap_with(other_target)
        system('tmux', 'swap-window', '-s', target, '-t', other_target)
      end

      def move_to(dest_target)
        system('tmux', 'move-window', '-s', target, '-t', dest_target)
      end

      def link_to(dest_session)
        system('tmux', 'link-window', '-s', target, '-t', dest_session)
      end

      def unlink
        system('tmux', 'unlink-window', '-t', target)
      end

      def to_h
        {
          id: id,
          index: index,
          name: name,
          active: active?,
          panes: panes,
          session_name: session_name
        }.compact
      end

      def to_s
        "#{session_name}:#{index} #{name} [#{panes} panes]#{active? ? ' *' : ''}"
      end
    end
  end
end
