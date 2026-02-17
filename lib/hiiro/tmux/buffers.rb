class Hiiro
  class Tmux
    class Buffers
      include Enumerable

      def self.fetch
        output = `tmux list-buffers -F '#{Buffer::FORMAT}' 2>/dev/null`
        return new([]) if output.nil? || output.empty?

        buffers = output.each_line.map { |line| Buffer.from_format_line(line) }.compact
        new(buffers)
      end

      attr_reader :buffers

      def initialize(buffers)
        @buffers = buffers
      end

      def each(&block)
        buffers.each(&block)
      end

      def find_by_name(name)
        buffers.find { |b| b.name == name }
      end

      def matching(pattern)
        regex = Regexp.new(pattern)
        self.class.new(buffers.select { |b| b.name =~ regex || b.sample =~ regex })
      end

      def names
        buffers.map(&:name)
      end

      def name_map
        buffers.each_with_object({}) do |buffer, h|
          h[buffer.to_s] = buffer.name
        end
      end

      def empty?
        buffers.empty?
      end

      def size
        buffers.size
      end
      alias count size
      alias length size

      def clear_all
        buffers.each(&:delete)
      end
    end
  end
end
