$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "ostruct"

# Use in-memory SQLite for tests so model files load cleanly and no real DB is touched
ENV['HIIRO_TEST_DB'] = 'sqlite::memory:'

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

# Create tables so Sequel models are usable in tests
Hiiro::DB.setup!

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

  def with_yaml_file(data)
    require 'yaml'
    with_temp_dir do |dir|
      path = File.join(dir, "test.yml")
      File.write(path, YAML.dump(data))
      yield path, dir
    end
  end
end

# Shared mock for Hiiro instance used by plugins
class MockHiiro
  attr_reader :bin_name, :subcmds, :attached_methods, :args

  def initialize(bin_name = "h", args: [])
    @bin_name = bin_name
    @subcmds = {}
    @attached_methods = []
    @args = args
  end

  def add_subcmd(*names, &block)
    names.each { |name| @subcmds[name.to_sym] = block }
  end

  def instance_eval(&block)
    super(&block)
  end

  def define_singleton_method(name, &block)
    @attached_methods << name
    super(name, &block)
  end
end

# DEPRECATED: Use Hiiro::Effects::NullExecutor instead.
# SystemCallCapture patches Kernel.system globally and has no awareness
# of which command type is being called. Prefer injecting NullExecutor
# via null_tmux / null_git helpers in TestHarness.
module SystemCallCapture
  def self.included(base)
    base.class_eval do
      attr_reader :system_calls

      def setup
        super if defined?(super)
        @system_calls = []
      end

      def capture_system_calls
        calls = @system_calls
        original_system = Kernel.method(:system)

        Kernel.define_method(:system) do |*args|
          calls << args
          true
        end

        yield
      ensure
        Kernel.define_method(:system, original_system)
      end
    end
  end
end

# Test harness for loading bin files and testing subcommands
# without duplicating subcommand code in tests
class Hiiro
  class TestHarness
    attr_reader :system_calls, :subcmds, :backtick_calls

    def initialize
      @system_calls = []
      @backtick_calls = []
      @backtick_responses = {}
      @subcmds = {}
      @default_subcmd = nil
    end

    # Stub system to capture calls
    def system(*args)
      @system_calls << args
      true
    end

    # Stub backticks - call stub_backtick to set responses
    def `(cmd)
      @backtick_calls << cmd
      @backtick_responses[cmd] || ""
    end

    def stub_backtick(cmd, response)
      @backtick_responses[cmd] = response
    end

    # Capture subcommand registrations
    def add_subcmd(*names, **opts, &block)
      names.each { |name| @subcmds[name.to_sym] = block }
    end

    # Capture default subcommand
    def add_default(&block)
      @default_subcmd = block
    end

    # Run a specific subcommand with args
    def run_subcmd(name, *args)
      block = @subcmds[name.to_sym]
      raise "Unknown subcmd: #{name}. Available: #{@subcmds.keys.inspect}" unless block
      instance_exec(*args, &block)
    end

    # Run the default subcommand
    def run_default(*args)
      raise "No default subcmd defined" unless @default_subcmd
      instance_exec(*args, &@default_subcmd)
    end

    # Check if a subcommand exists
    def has_subcmd?(name)
      @subcmds.key?(name.to_sym)
    end

    # List all registered subcommands
    def subcmd_names
      @subcmds.keys
    end

    # Clear recorded calls (useful between tests)
    def reset_calls!
      @system_calls.clear
      @backtick_calls.clear
    end

    # Load a bin file and capture its block
    # Pass a block to pre-configure stubs before the bin's block is evaled
    def self.load_bin(bin_path, &setup_block)
      harness = new
      block = nil

      # Apply pre-setup stubs (e.g., tmux_client) before loading
      harness.instance_eval(&setup_block) if setup_block

      # Temporarily replace Hiiro.run to capture the block
      original_run = Hiiro.method(:run)
      Hiiro.define_singleton_method(:run) do |*args, **kwargs, &blk|
        block = blk
      end

      # Load the bin file — anchor to project root, not Dir.pwd (which may differ)
      full_path = File.expand_path(bin_path, File.join(__dir__, '..'))
      load full_path

      # Restore original Hiiro.run
      Hiiro.define_singleton_method(:run, original_run)

      # Eval the block in our harness context
      harness.instance_eval(&block) if block
      harness
    end

    # Allow tests to add stub methods to the harness
    def stub_method(name, &block)
      define_singleton_method(name, &block)
    end

    # Stubs for Hiiro#add_resolver / #resolve — called by Hiiro::Tmux.add_resolvers during load_bin.
    def add_resolver(name, current = nil, &lookup)
      @resolvers ||= {}
      @resolvers[name.to_sym] = { current:, lookup: }
    end

    def resolve(name, ref = nil)
      @resolvers ||= {}
      r = @resolvers[name.to_sym] or raise "No resolver registered for :#{name}"
      if ref.nil?
        c = r[:current]
        c.respond_to?(:call) ? c.call : c
      else
        r[:lookup]&.call(ref)
      end
    end

    # Stub for Hiiro#edit_files — routes through system() so system_calls is populated,
    # matching the real implementation's behavior. Uses $EDITOR or 'vim' as fallback.
    def edit_files(*files, max_splits: 3)
      system(ENV['EDITOR'] || 'vim', *files)
    end

    # Initialize Effects doubles. After calling this:
    #   harness.executor        → NullExecutor (shared by null_tmux + null_git)
    #   harness.fs              → NullFilesystem
    #   harness.null_tmux       → Hiiro::Tmux with executor injected
    #   harness.null_git        → Hiiro::Git  with executor injected
    #   harness.null_fs         → the same NullFilesystem instance
    def setup_effects
      @executor = Hiiro::Effects::NullExecutor.new
      @fs       = Hiiro::Effects::NullFilesystem.new
    end

    attr_reader :executor, :fs

    def null_tmux = Hiiro::Tmux.new(executor: @executor)
    def null_git  = Hiiro::Git.new(nil, '/fake/root', executor: @executor)
    def null_fs   = @fs
  end
end
