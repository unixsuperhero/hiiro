class Hiiro
  class Tmux
    class Windows
      include Enumerable

      def self.fetch(session: nil, all: false)
        args = ['tmux', 'list-windows', '-F', Window::FORMAT]
        args << '-a' if all
        args += ['-t', session] if session && !all

        output = `#{args.shelljoin} 2>/dev/null`
        return new([]) if output.nil? || output.empty?

        windows = output.each_line.map { |line| Window.from_format_line(line) }.compact
        new(windows)
      end

      attr_reader :windows

      def initialize(windows)
        @windows = windows
      end

      def each(&block)
        windows.each(&block)
      end

      def find_by_id(id)
        windows.find { |w| w.id == id }
      end

      def find_by_name(name)
        windows.find { |w| w.name == name }
      end

      def find_by_index(index)
        windows.find { |w| w.index == index }
      end

      def in_session(session_name)
        self.class.new(windows.select { |w| w.session_name == session_name })
      end

      def active
        self.class.new(windows.select(&:active?))
      end

      def names
        windows.map(&:name)
      end

      def targets
        windows.map(&:target)
      end

      def empty?
        windows.empty?
      end

      def size
        windows.size
      end
      alias count size
      alias length size
    end
  end
end
