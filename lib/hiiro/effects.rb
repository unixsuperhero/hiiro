require 'fileutils'
require 'shellwords'

class Hiiro
  module Effects
    # Real implementation — delegates to the OS
    class Executor
      def capture(*args) = `#{args.shelljoin} 2>/dev/null`
      def run(*args)     = system(*args)
      def check(*args)   = system(*args, out: File::NULL, err: File::NULL)
    end

    # Test double — records every call, returns configured stubs.
    # Usage:
    #   ex = NullExecutor.new
    #   ex.stub('new-window', '')        # stub any call containing 'new-window'
    #   tmux = Hiiro::Tmux.new(executor: ex)
    #   tmux.new_window('mysession', 'main')
    #   assert ex.called?('new-window')
    class NullExecutor
      attr_reader :calls

      def initialize
        @calls = []
        @stubs = {}
      end

      # Register a stub. pattern is matched as a substring of the joined args string.
      def stub(pattern, output = '')
        @stubs[pattern.to_s] = output
      end

      def capture(*args)
        record(:capture, args)
        find_stub(args) || ''
      end

      def run(*args)
        record(:run, args)
        result = find_stub(args)
        result.nil? ? true : result
      end

      def check(*args)
        record(:check, args)
        result = find_stub(args)
        result.nil? ? true : !!result
      end

      # Returns true if any recorded call contains pattern as a substring of any arg.
      def called?(pattern)
        @calls.any? { |c| c[:args].any? { |a| a.to_s.include?(pattern.to_s) } }
      end

      # Returns all calls to a given method (:capture, :run, :check).
      def calls_to(method)
        @calls.select { |c| c[:method] == method }
      end

      # Clear all recorded calls (useful between test assertions).
      def reset!
        @calls = []
      end

      private

      def record(method, args)
        @calls << { method: method, args: args }
      end

      def find_stub(args)
        key = args.map(&:to_s).join(' ')
        match = @stubs.find { |pat, _| key.include?(pat) }
        match&.last
      end
    end

    # Real filesystem implementation.
    class Filesystem
      def write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def read(path)        = File.read(path)
      def exist?(path)      = File.exist?(path)
      def mkdir_p(path)     = FileUtils.mkdir_p(path)
      def glob(pattern)     = Dir.glob(pattern)
      def rm(path)          = File.exist?(path) ? File.delete(path) : nil
      def mv(src, dst)      = FileUtils.mv(src, dst)
      def rename(src, dst)  = File.rename(src, dst)
    end

    # In-memory filesystem double for tests.
    # Does not touch the real filesystem.
    # Usage:
    #   fs = NullFilesystem.new
    #   manager = Hiiro::TodoManager.new(fs: fs)
    #   manager.save
    #   assert_includes fs.writes, TodoManager::TODO_FILE
    class NullFilesystem
      attr_reader :writes, :deletes, :renames

      def initialize
        @store   = {}   # path → content
        @writes  = []
        @deletes = []
        @renames = []
      end

      def write(path, content)
        @writes << path
        @store[path] = content
      end

      def read(path)
        @store.fetch(path) { raise Errno::ENOENT, path }
      end

      def exist?(path)  = @store.key?(path)
      def mkdir_p(path) = nil
      def glob(pattern) = @store.keys.select { |k| File.fnmatch(pattern, k) }

      def rm(path)
        @deletes << path
        @store.delete(path)
      end

      def mv(src, dst)
        @store[dst] = @store.delete(src)
        @renames << [src, dst]
      end

      def rename(src, dst)
        mv(src, dst)
      end

      # Retrieve what was written to path (for assertions).
      def content_at(path)
        @store[path]
      end

      # Reset state between tests.
      def reset!
        @store   = {}
        @writes  = []
        @deletes = []
        @renames = []
      end
    end
  end
end
