class Hiiro
  class Tmux
    class Session
      FORMAT = '#{session_id}|#{session_name}|#{session_windows}|#{session_attached}|#{session_created}|#{session_last_attached}'

      attr_reader :id, :name, :windows, :created, :last_attached

      def self.from_format_line(line)
        return nil if line.nil? || line.strip.empty?

        parts = line.strip.split('|', 6)
        return nil if parts.size < 4

        id, name, windows, attached, created, last_attached = parts

        new(
          id: id,
          name: name,
          windows: windows.to_i,
          attached: attached == '1',
          created: created.to_i,
          last_attached: last_attached.to_i
        )
      end

      def self.current
        output = `tmux display-message -p '#{FORMAT}' 2>/dev/null`.strip
        return nil if output.empty?

        from_format_line(output)
      end

      def initialize(id:, name:, windows: 0, attached: false, created: 0, last_attached: 0)
        @id = id
        @name = name
        @windows = windows
        @attached = attached
        @created = created
        @last_attached = last_attached
      end

      def attached?
        @attached
      end

      def kill
        system('tmux', 'kill-session', '-t', name)
      end

      def rename(new_name)
        system('tmux', 'rename-session', '-t', name, new_name)
      end

      def select
        if ENV['TMUX']
          system('tmux', 'switch-client', '-t', name)
        else
          system('tmux', 'attach-session', '-t', name)
        end
      end

      def attach
        system('tmux', 'attach-session', '-t', name)
      end

      def detach
        system('tmux', 'detach-client', '-s', name)
      end

      def to_h
        {
          id: id,
          name: name,
          windows: windows,
          attached: attached?,
          created: created,
          last_attached: last_attached
        }.compact
      end

      def to_s
        "#{name} (#{windows} windows#{attached? ? ', attached' : ''})"
      end
    end
  end
end
