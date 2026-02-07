class Hiiro
  class Git
    class Branches
      include Enumerable

      def self.fetch(sort_by: nil, ignore_case: false, remote: false)
        args = ['git', 'branch', '--format=%(refname:short)']
        args << '-i' if ignore_case
        args << '-r' if remote
        args << "-a" if remote == :all
        args << "--sort=#{sort_by}" if sort_by

        output = `#{args.shelljoin} 2>/dev/null`
        from_names(output.split("\n").map(&:strip))
      end

      def self.from_names(names)
        branches = names.map { |name| Branch.new(name: name) }
        new(branches)
      end

      def self.local(sort_by: nil, ignore_case: false)
        fetch(sort_by: sort_by, ignore_case: ignore_case, remote: false)
      end

      def self.remote(sort_by: nil, ignore_case: false)
        fetch(sort_by: sort_by, ignore_case: ignore_case, remote: true)
      end

      def self.all(sort_by: nil, ignore_case: false)
        fetch(sort_by: sort_by, ignore_case: ignore_case, remote: :all)
      end

      attr_reader :branches

      def initialize(branches)
        @branches = branches
      end

      def each(&block)
        branches.each(&block)
      end

      def find_by_name(name)
        branches.find { |b| b.name == name }
      end

      def matching(prefix)
        self.class.new(branches.select { |b| b.name.start_with?(prefix) })
      end

      def containing(substring)
        self.class.new(branches.select { |b| b.name.include?(substring) })
      end

      def names
        branches.map(&:name)
      end

      def current
        branches.find(&:current?)
      end

      def empty?
        branches.empty?
      end

      def size
        branches.size
      end
      alias count size
      alias length size

      def to_a
        branches.dup
      end
    end
  end
end
