class Hiiro
  class Tmux
    class Sessions
      include Enumerable

      def self.fetch
        output = `tmux list-sessions -F '#{Session::FORMAT}' 2>/dev/null`
        return new([]) if output.nil? || output.empty?

        sessions = output.each_line.map { |line| Session.from_format_line(line) }.compact
        new(sessions)
      end

      attr_reader :sessions

      def initialize(sessions)
        @sessions = sessions
      end

      def each(&block)
        sessions.each(&block)
      end

      def find_by_id(id)
        sessions.find { |s| s.id == id }
      end

      def find_by_name(name)
        sessions.find { |s| s.name == name }
      end

      def attached
        self.class.new(sessions.select(&:attached?))
      end

      def detached
        self.class.new(sessions.reject(&:attached?))
      end

      def names
        sessions.map(&:name)
      end

      def empty?
        sessions.empty?
      end

      def size
        sessions.size
      end
      alias count size
      alias length size
    end
  end
end
