class Hiiro
  class Git
    class Branch
      attr_reader :name, :ref, :upstream, :head

      def self.from_format_line(line, format: :short)
        # Parses output from git branch --format
        new(name: line.strip)
      end

      def self.current
        name = `git branch --show-current 2>/dev/null`.strip
        return nil if name.empty?
        new(name: name, current: true)
      end

      def initialize(name:, ref: nil, upstream: nil, head: nil, current: false)
        @name = name
        @ref = ref || "refs/heads/#{name}"
        @upstream = upstream
        @head = head
        @current = current
      end

      def current?
        @current
      end

      def local?
        ref.start_with?('refs/heads/')
      end

      def remote?
        ref.start_with?('refs/remotes/')
      end

      def checkout
        system('git', 'checkout', name)
      end

      def delete(force: false)
        flag = force ? '-D' : '-d'
        system('git', 'branch', flag, name)
      end

      def exists?
        system('git', 'show-ref', '--verify', '--quiet', ref)
      end

      def to_s
        name
      end

      def to_h
        {
          name: name,
          ref: ref,
          upstream: upstream,
          head: head,
          current: current?,
        }.compact
      end
    end
  end
end
