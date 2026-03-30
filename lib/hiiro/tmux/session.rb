class Hiiro
  class Tmux
    class Session
      FORMAT = '#{session_id}|#{session_name}|#{session_windows}|#{session_attached}|#{session_created}|#{session_last_attached}|#{session_path}'

      attr_reader :id, :name, :windows, :created, :last_attached, :path

      def self.from_format_line(line)
        return nil if line.nil? || line.strip.empty?

        parts = line.strip.split('|', 7)
        return nil if parts.size < 4

        id, name, windows, attached, created, last_attached, path = parts

        new(
          id: id,
          name: name,
          windows: windows.to_i,
          attached: attached == '1',
          created: created.to_i,
          last_attached: last_attached.to_i,
          path: path
        )
      end

      def self.current
        output = `tmux display-message -p '#{FORMAT}' 2>/dev/null`.strip
        return nil if output.empty?

        from_format_line(output)
      end

      def self.all
        output = `tmux list-sessions -F '#{FORMAT}' 2>/dev/null`
        return [] if output.nil? || output.empty?

        output.each_line.map { |line| from_format_line(line) }.compact
      end

      def self.client_map
        output = `tmux list-clients -F '\#{client_tty}|\#{session_name}' 2>/dev/null`
        output.lines(chomp: true).each_with_object({}) do |line, map|
          tty, session_name = line.split('|', 2)
          map[session_name] ||= tty.delete_prefix('/dev/')
        end
      end

      def initialize(id:, name:, windows: 0, attached: false, created: 0, last_attached: 0, path: nil)
        @id = id
        @name = name
        @windows = windows
        @attached = attached
        @created = created
        @last_attached = last_attached
        @path = path
      end

      def ==(other)
        other.is_a?(Session) && name == other.name
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
          system('tmux', 'switch-client', '-t', "=#{name}")
        else
          system('tmux', 'attach-session', '-t', "=#{name}")
        end
      end

      def attach
        system('tmux', 'attach-session', '-t', "=#{name}")
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
          last_attached: last_attached,
          path: path
        }.compact
      end

      def to_s
        "#{name} (#{windows} windows#{attached? ? ', attached' : ''})"
      end
    end
  end
end
