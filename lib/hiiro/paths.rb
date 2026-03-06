#!/usr/bin/env ruby

require "hiiro"
require "delegate"

class Hiiro
  class Paths
    attr_reader :base

    def initialize(base=Dir.pwd)
      @base = Pathname.new base
    end

    def from_base(file)
      path = Pathname.new(file)
      path.relative_path_from(base)
    end

    def symlinks_in(path)
      subdir = Pathname.new(path)

      subdir.find
        .select(&:symlink?)
        .map { |link| Symlink.new(link) }
    end

    class Symlink < SimpleDelegator
      def path
        @path ||= Pathname.new(__getobj__)
      end

      def dest
        path.readlink
      end

      def root
        `git rev-parse --show-toplevel 2>/dev/null`.chomp
      end

      def root_path
        Pathname.new root
      end

      def dest_from_root
        abs = (path.dirname + dest).cleanpath
        abs.relative_path_from(root_path)
      end

      def dest_relative_to(base_dir)
        abs = (path.dirname + dest).cleanpath
        abs.relative_path_from(Pathname.new(base_dir))
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
