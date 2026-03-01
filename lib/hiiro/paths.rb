#!/usr/bin/env ruby

require "hiiro"

class Hiiro
  class Paths
    attr_reader :base

    def initialize(base)
      @base = Pathname.new base
    end

    def child(path)
      if File.absolute_path?(path)
        Pathname.new(path)
      else
        base.join path
      end
    end

    def symlinks_in(path)
      subdir = child(path)

      subdir.find.select(&:symlink?)
    end

    def symlink_dest(link)
      link.readlink.expand_path(link.dirname)
    end

    def outside_dir?(file, dir)
      relative_path = file.relative_path_from(dir)

      relative_path.descend.first == Pathname.new('..')
    end
  end
end
