$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "ostruct"

# Stub out plugin loading to avoid side effects during tests
class Hiiro
  class Config
    class << self
      def plugin_files
        []
      end
    end
  end
end

require "hiiro"

module TestHelpers
  def with_temp_dir
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  def with_temp_file(content = "", extension = ".txt")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test#{extension}")
      File.write(path, content)
      yield path
    end
  end
end
