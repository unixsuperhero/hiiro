class Hiiro
  class Git
    class Worktree
      attr_reader :path, :head, :branch

      def self.from_porcelain_block(lines)
        attrs = {}
        lines.each do |line|
          case line
          when /^worktree (.+)/
            attrs[:path] = $1
          when /^HEAD (.+)/
            attrs[:head] = $1
          when /^branch refs\/heads\/(.+)/
            attrs[:branch] = $1
          when 'detached'
            attrs[:detached] = true
          when 'bare'
            attrs[:bare] = true
          end
        end
        new(**attrs) if attrs[:path]
      end

      def initialize(path:, head: nil, branch: nil, detached: false, bare: false)
        @path = path
        @head = head
        @branch = branch
        @detached = detached
        @bare = bare
      end

      def detached?
        @detached
      end

      def bare?
        @bare
      end

      def name
        File.basename(path)
      end

      def match?(pwd)
        pwd == path || pwd.start_with?(path + '/')
      end

      def to_h
        {
          path: path,
          head: head,
          branch: branch,
          detached: detached?,
          bare: bare?,
        }.compact
      end
    end
  end
end
