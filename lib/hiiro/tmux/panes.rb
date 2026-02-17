class Hiiro
  class Tmux
    class Panes
      include Enumerable

      def self.fetch(target: nil, all: false)
        args = ['tmux', 'list-panes', '-F', Pane::FORMAT]
        args << '-a' if all
        args += ['-t', target] if target && !all

        output = `#{args.shelljoin} 2>/dev/null`
        return new([]) if output.nil? || output.empty?

        panes = output.each_line.map { |line| Pane.from_format_line(line) }.compact
        new(panes)
      end

      attr_reader :panes

      def initialize(panes)
        @panes = panes
      end

      def each(&block)
        panes.each(&block)
      end

      def find_by_id(id)
        panes.find { |p| p.id == id }
      end

      def find_by_index(index)
        panes.find { |p| p.index == index }
      end

      def in_window(window_id)
        self.class.new(panes.select { |p| p.window_id == window_id })
      end

      def in_session(session_name)
        self.class.new(panes.select { |p| p.session_name == session_name })
      end

      def active
        self.class.new(panes.select(&:active?))
      end

      def by_command(command)
        self.class.new(panes.select { |p| p.command == command })
      end

      def by_path(path)
        self.class.new(panes.select { |p| p.path == path })
      end

      def ids
        panes.map(&:id)
      end

      def targets
        panes.map(&:target)
      end

      def name_map
        panes.each_with_object({}) do |pane, h|
          h[pane.to_s] = pane.id
        end
      end

      def empty?
        panes.empty?
      end

      def size
        panes.size
      end
      alias count size
      alias length size
    end
  end
end
