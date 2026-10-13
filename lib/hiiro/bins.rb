class Hiiro
  # Executable lookup over PATH, read at call time. An eligible candidate is a
  # regular file (or a symlink that resolves to one) with the executable bit;
  # directories, non-executables, and broken links are skipped. PATH is read in
  # order: an empty entry means the current directory (as in the shell),
  # relative entries resolve against the current directory, and a repeated
  # directory is searched once at its first position.
  class Bins
    def self.path = ENV['PATH'].to_s

    def self.paths(path = self.path)
      path.split(File::PATH_SEPARATOR, -1).map { |dir| File.expand_path(dir.empty? ? '.' : dir) }.uniq
    end

    def self.eligible?(file) = File.file?(file) && File.executable?(file)

    # Eligible paths for the given glob patterns, in PATH order, then by name within a directory.
    def self.glob(*names, path: self.path)
      patterns = names.flatten.compact
      paths(path).flat_map { |dir|
        patterns.flat_map { |pattern| Dir.glob(pattern, base: dir) }.uniq.sort.map { |name| File.join(dir, name) }
      }.select { |file| eligible?(file) }
    end

    def self.all(path: self.path) = glob('*', path:)

    def self.which(name, path: self.path)
      paths(path).map { |dir| File.join(dir, name) }.find { |file| eligible?(file) }
    end
  end
end
