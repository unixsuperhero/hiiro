class Hiiro
  class Git
    class Remote
      attr_reader :name, :fetch_url, :push_url

      def self.all
        output = `git remote 2>/dev/null`
        output.split("\n").map { |name| new(name: name.strip) }
      end

      def self.origin
        new(name: 'origin')
      end

      def self.from_verbose_line(line)
        # Parses: origin	git@github.com:user/repo.git (fetch)
        match = line.match(/^(\S+)\s+(\S+)\s+\((fetch|push)\)/)
        return nil unless match

        name, url, type = match.captures
        attrs = { name: name }
        attrs[type == 'fetch' ? :fetch_url : :push_url] = url
        new(**attrs)
      end

      def initialize(name:, fetch_url: nil, push_url: nil)
        @name = name
        @fetch_url = fetch_url
        @push_url = push_url
      end

      def url
        fetch_url || push_url || fetch_remote_url
      end

      def push(branch = nil, force: false)
        args = ['git', 'push', name]
        args << '-f' if force
        args << branch if branch
        system(*args)
      end

      def pull(branch = nil)
        args = ['git', 'pull', name]
        args << branch if branch
        system(*args)
      end

      def fetch_remote
        system('git', 'fetch', name)
      end

      def exists?
        system('git', 'remote', 'get-url', name, out: File::NULL, err: File::NULL)
      end

      def to_s
        name
      end

      def to_h
        {
          name: name,
          fetch_url: fetch_url,
          push_url: push_url,
        }.compact
      end

      private

      def fetch_remote_url
        url = `git remote get-url #{name.shellescape} 2>/dev/null`.strip
        url.empty? ? nil : url
      end
    end
  end
end
