#!/usr/bin/env ruby

require "hiiro"
require "delegate"

class Hiiro
  class Paths
    attr_reader :base, :hiiro

    def initialize(base=Dir.pwd, hiiro: nil)
      @base = Pathname.new base
      @hiiro = hiiro
    end

    def from_base(file)
      path = Pathname.new(file)
      path.relative_path_from(base)
    end

    def symlinks_in(path)
      subdir = Pathname.new(path).expand_path

      subdir.find
        .select(&:symlink?)
        .map { |link| Symlink.new(link, hiiro) }
    end

    # Returns [full_path, unique_name] — appends -2, -3, etc. if a file
    # with the same base_name already exists in dir.
    def self.unique_path(dir, base_name, ext: '.md')
      name = base_name
      counter = 1
      while File.exist?(File.join(dir, "#{name}#{ext}"))
        counter += 1
        name = "#{base_name}-#{counter}"
      end
      [File.join(dir, "#{name}#{ext}"), name]
    end

    class Symlink < SimpleDelegator
      attr_reader :hiiro

      def initialize(path, hiiro=nil)
        @hiiro = hiiro
        super(path)
      end

      def path
        @path ||= Pathname.new(__getobj__)
      end

      def dest
        path.readlink
      end

      def root
        @root ||= hiiro&.git&.root || `git rev-parse --show-toplevel 2>/dev/null`.chomp
      end

      def root_path
        Pathname.new root
      end

      def abs_dest
        (path.dirname + dest).cleanpath
      end

      def dest_from_root
        abs_dest.relative_path_from(root_path)
      end

      def dest_relative_to(base_dir)
        abs_dest.relative_path_from(Pathname.new(base_dir))
      end

      def dest_dir
        path.directory? ? path : path.dirname
      end

      def dest_in_dir?(dir)
        dir = Pathname.new(dir)

        relpath = dest.relative_path_from(dir)
        relpath.descend.first.to_s != '..'
      end
    end
  end
end
