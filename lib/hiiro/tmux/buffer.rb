class Hiiro
  class Tmux
    class Buffer
      FORMAT = '#{buffer_name}|#{buffer_size}|#{buffer_created}|#{buffer_sample}'

      attr_reader :name, :size, :created, :sample

      def self.from_format_line(line)
        return nil if line.nil? || line.strip.empty?

        parts = line.strip.split('|', 4)
        return nil if parts.size < 3

        name, size, created, sample = parts

        new(
          name: name,
          size: size.to_i,
          created: created.to_i,
          sample: sample
        )
      end

      def initialize(name:, size: 0, created: 0, sample: nil)
        @name = name
        @size = size
        @created = created
        @sample = sample
      end

      def content
        `tmux show-buffer -b #{name.shellescape} 2>/dev/null`
      end

      def delete
        system('tmux', 'delete-buffer', '-b', name)
      end

      def paste(target: nil)
        args = ['tmux', 'paste-buffer', '-b', name]
        args += ['-t', target] if target
        system(*args)
      end

      def save(path)
        system('tmux', 'save-buffer', '-b', name, path)
      end

      def to_h
        {
          name: name,
          size: size,
          created: created,
          sample: sample
        }.compact
      end

      def to_s
        "#{name}: #{sample}"
      end
    end
  end
end
