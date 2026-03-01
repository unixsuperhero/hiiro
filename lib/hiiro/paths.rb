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
