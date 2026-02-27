require "fileutils"
require "yaml"
require "shellwords"
require "pry"

require_relative "hiiro/version"
require_relative "hiiro/matcher"
require_relative "hiiro/git"
require_relative "hiiro/options"
require_relative "hiiro/notification"
require_relative "hiiro/fuzzyfind"
require_relative "hiiro/todo"
require_relative "hiiro/tmux"
require_relative "hiiro/tasks"
require_relative "hiiro/queue"

class String
  def underscore(camel_cased_word=self)
    regex = /(?:(?<=([A-Za-z\d]))|\b)((?-mix:(?=a)b))(?=\b|[^a-z])/
    return camel_cased_word.to_s.dup unless /[A-Z-]|::/.match?(camel_cased_word)
    word = camel_cased_word.to_s.gsub("::", "/")
    word.gsub!(regex) { "#{$1 && '_' }#{$2.downcase}" }
    word.gsub!(/(?<=[A-Z])(?=[A-Z][a-z])|(?<=[a-z\d])(?=[A-Z])/, "_")
    word.tr!("-", "_")
    word.downcase!
    word
  end
end

class Hiiro
  WORK_DIR = File.join(Dir.home, 'work')
  REPO_PATH = File.join(WORK_DIR, '.bare')

  def self.init(*oargs, plugins: [], logging: false, tasks: false, task_scope: nil, **values, &block)
    load_env

    if values[:args]
      args = values[:args]
    else
      args ||= oargs
      args = ARGV if args.empty?
    end

    bin_name = values[:bin_name] || $0

    new(bin_name, *args, logging: logging, tasks: tasks, task_scope: task_scope, **values).tap do |hiiro|
      hiiro.load_plugins(plugins)

      hiiro.add_subcommand(:pry) { |*args|
        binding.pry
      }

      hiiro.add_subcmd(:edit, **values) { |*args|
        system(ENV['EDITOR'] || 'nvim', hiiro.bin)
      }

      if hiiro.tasks_enabled?
        hiiro.add_subcmd(:task) do |*args|
          tm = TaskManager.new(hiiro, scope: :task)
          Tasks.build_hiiro(hiiro, tm).run
        end

        hiiro.add_subcmd(:subtask) do |*args|
          tm = TaskManager.new(hiiro, scope: :subtask)
          Tasks.build_hiiro(hiiro, tm).run
        end
      end

      if block
        if block.arity == 1
          block.call(hiiro)
        else
          hiiro.instance_eval(&block)
        end
      end
    end
  end

  def self.run(*args, plugins: [], logging: false, tasks: false, task_scope: nil, **values, &block)
    hiiro = init(*args, plugins:, logging:, tasks:, task_scope:, **values, &block)

    hiiro.run
  end

  def self.load_env
    Config.plugin_files.each do |plugin_file|
      require plugin_file
    end

    self
  end

  attr_reader :bin, :bin_name, :all_args, :full_command
  attr_reader :subcmd, :args
  attr_reader :loaded_plugins
  attr_reader :logging
  attr_reader :global_values
  attr_reader :task_scope

  def initialize(bin, *all_args, logging: false, tasks: false, task_scope: nil, **values)
    @bin = bin
    @bin_name = File.basename(bin)
    @all_args = all_args
    @subcmd, *@args = all_args # normally i would never do this
    @loaded_plugins = []
    @logging = logging
    @tasks_enabled = tasks
    @task_scope = task_scope
    @global_values = values
    @full_command = [
      bin_name,
      *all_args,
    ].map(&:shellescape).join(' ')
  end

  def tasks_enabled?
    @tasks_enabled
  end

  def environment
    @environment ||= Environment.current
  end
  alias env environment

  def task_manager
    return nil unless tasks_enabled?
    @task_manager ||= TaskManager.new(self, scope: task_scope || :task)
  end
  alias tm task_manager

  def tasks
    task_manager&.tasks
  end

  def tmux_client
    @tmux_client ||= Tmux.client!(self)
  end

  def start_tmux_session(name)
    tmux_client.open_session(name)
  end

  def make_child(subcmd, *args, **kwargs, &block)
    bin_name = [bin, subcmd.to_s].join(?-)

    Hiiro.init(bin_name:, args:, **kwargs, &block)
  end

  def todo_manager
    @todo_manager ||= TodoManager.new
  end

  def queue
    @queue ||= Queue.current
  end

  def run
    result = runner.run(*args)

    handle_result(result)

    exit 1
  rescue => e
    puts "ERROR: #{e.message}"
    puts e.backtrace
    exit 1
  end

  def handle_result(result)
    exit 0 if result.nil? || result

    exit 1
  end

  def runnable?
    runner
  end

  def runner
    runners.runner || runners.default_subcommand
  end

  def runners
    @runners ||= Runners.new(self)
  end

  def add_default(**values, &handler)
    runners.add_default(handler, **global_values, **values)
  end

  def add_subcommand(*names, **values, &handler)
    names.each do |name|
      runners.add_subcommand(name, handler, **global_values, **values)
    end
  end
  alias add_subcmd add_subcommand

  def run_subcommand(name, *args)
    runners.run_subcommand(name, *args)
  end
  alias run_subcmd run_subcommand

  def full_name
    runner&.full_name || [bin_name, subcmd].join(?-)
  end

  def subcommand_names
    runners.subcommand_names
  end

  def pins = @pins ||= Pin.new(self)

  def git
    @git ||= Git.new(self, Dir.pwd)
  end

  def attach_method(name, &block)
    define_singleton_method(name.to_sym, &block)
  end

  def load_plugins(*plugins)
    plugins.flatten.each { |plugin| load_plugin(plugin) }
  end

  def load_plugin(plugin_const)
    if plugin_const.is_a?(String) || plugin_const.is_a?(Symbol)
      begin
        plugin_const = Kernel.const_get(plugin_const.to_sym)
      rescue => e
        puts "unable to load plugin: #{plugin_const}"
        puts "Error message: #{e.message}"
        return
      end
    end

    return if @loaded_plugins.include?(plugin_const)

    plugin_const.load(self)
    @loaded_plugins.push(plugin_const)
  end

  def help(options=nil)
    ambiguous = runners.ambiguous_matches

    puts "Current command: #{bin_name}!"

    if ambiguous.any?
      puts "Ambiguous subcommand #{subcmd.inspect}!"
      puts
      puts "Did you mean one of these?"
      list_runners(ambiguous)
      puts
    else
      puts "Subcommand required for #{bin_name}"
      puts
      puts "Possible subcommands:"
      list_runners(runners.all_runners)
      puts
    end

    if options
      puts "Options:"
      puts options.help_text
      puts
    end

    exit 1
  end

  def list_runners(list)
    max_name = list.map { |r| r.subcommand_name.length }.max || 0
    max_type = list.map { |r| r.type.to_s.length }.max || 0
    max_params = list.map { |r| r.params_string.to_s.length }.max || 0

    list.each do |r|
      name = r.subcommand_name.ljust(max_name)
      type = "(#{r.type})".ljust(max_type + 2)
      params = r.params_string
      params_col = params ? params.ljust(max_params) : ''.ljust(max_params)
      location = r.location
      puts "  #{name}  #{params_col}  #{type}  #{location}"
    end
  end

  def log(message)
    return unless logging

    puts "[Hiiro: #{bin_name} #{(runner&.subcommand_name || subcmd).inspect}]: #{message}"
  end

  def parsed_args
    i = Args.new(*args)
  end

  def fuzzyfind(lines)
    Fuzzyfind.select(lines)
  end

  def fuzzyfind_from_map(mapping)
    Fuzzyfind.map_select(mapping)
  end

  def get_value(name)
    runner&.values&.[](name)
  end

  class Config
    class << self
      def plugin_files
        user_files = Dir.glob(File.join(plugin_dir, '*.rb'))
        user_basenames = user_files.map { |f| File.basename(f) }

        gem_plugin_dir = File.join(File.expand_path('../..', __FILE__), 'plugins')
        gem_files = Dir.exist?(gem_plugin_dir) ? Dir.glob(File.join(gem_plugin_dir, '*.rb')) : []

        fallback_files = gem_files.reject { |f| user_basenames.include?(File.basename(f)) }

        user_files + fallback_files
      end

      def plugin_dir
        config_dir('plugins')
      end

      def config_dir(subdir=nil)
        File.join(Dir.home, '.config/hiiro', *[subdir].compact).tap do |config_path|
          FileUtils.mkdir_p(config_path) unless Dir.exist?(config_path)
        end
      end
    end
  end

  def default_subcommand
    Runners::Subcommand.new(
      bin_name,
      :DEFAULT,
      lambda { |*args| help; false },
    )
  end

  class Runners
    attr_reader :hiiro, :bin_name, :subcmd, :subcommands

    def initialize(hiiro)
      @hiiro = hiiro
      @bin_name = hiiro.bin_name
      @subcmd = hiiro.subcmd
      @subcommands = {}
      @default_subcommand = hiiro.default_subcommand
    end

    def add_default(handler, **values)
      @default_subcommand = Subcommand.new(
        bin_name,
        :DEFAULT,
        handler,
        **values
      )
    end

    def runner
      return exact_runner if exact_runner
      return unambiguous_runner if unambiguous_runner

      @default_subcommand
    end

    def subcommand_names
      all_runners.map(&:subcommand_name)
    end

    def all_runners
      [*all_bins, *subcommands.values]
    end

    def paths
      @paths ||= ENV['PATH'].split(?:).uniq
    end

    def all_bins
      pattern = format('{%s}/%s-*', paths.join(?,), bin_name)

      Dir.glob(pattern).map { |path| Bin.new(bin_name, path) }
    end

    def add_subcommand(name, handler, **values)
      @subcommands[name] = Subcommand.new(bin_name, name, handler, values)
    end

    def run_subcommand(name, *args)
      cmd = subcommands[name]

      cmd&.run(*args)
    end

    def exact_runner
      all_runners.find { |r| r.exact_match?(subcmd) }
    end

    def unambiguous_runner
      return nil if subcmd.nil?

      matches = matching_runners
      return matches.first if matches.count == 1

      nil
    end

    def ambiguous_matches
      return [] if subcmd.nil?

      matches = matching_runners
      return matches if matches.count > 1

      []
    end

    def matching_runners
      remove_child_runners(all_matching_runners)
    end

    def all_matching_runners
      all_runners.select { |r| r.match?(subcmd) }
    end

    def remove_child_runners(list)
      list.reject do |r|
        list.any? { |other| r != other && r.full_name.start_with?(other.full_name + ?-) }
      end
    end

    class Bin
      attr_reader :bin_name, :path, :name
      alias full_name name

      def initialize(bin_name, path)
        @bin_name = bin_name
        @path = path
        @name = File.basename(path)
      end

      def run(*args)
        system(path, *args)
      end

      def exact_match?(subcmd)
        subcommand_name == subcmd.to_s
      end

      def match?(subcmd)
        subcommand_name.start_with?(subcmd.to_s)
      end

      def subcommand_name
        name.sub("#{bin_name}-", '')
      end

      def values
        {}
      end

      def type
        :bin
      end

      def location
        path
      end

      def params_string
        nil
      end
    end

    class Subcommand
      attr_reader :bin_name, :name, :handler, :values
      alias subcommand_name name

      def initialize(bin_name, name, handler, values={})
        @bin_name = bin_name
        @name = name.to_s
        @handler = handler
        @values = values || {}
      end

      def run(*args)
        handler.call(*args)
      end

      def exact_match?(subcmd)
        name == subcmd.to_s
      end

      def match?(subcmd)
        name.start_with?(subcmd.to_s)
      end

      def full_name
        [bin_name, name].join(?-)
      end

      def type
        :subcommand
      end

      def location
        handler.source_location&.join(':')
      end

      def params_string
        return nil unless handler.respond_to?(:parameters)

        params = handler.parameters
        return nil if params.empty?
        return nil if params == [[:rest]] || params == [[:rest, :args]]

        params.map { |type, name|
          case type
          when :req then "<#{name}>"
          when :opt then "[#{name}]"
          when :rest then "[*#{name}]" if name
          when :keyreq then "<#{name}:>"
          when :key then "[#{name}:]"
          when :keyrest then "[**#{name}]" if name
          when :block then "[&#{name}]" if name
          end
        }.compact.join(' ')
      end
    end
  end

  class Args
    attr_reader :raw_args

    def initialize(*raw_args)
      @raw_args = raw_args
    end

    def flags
      @flags ||= proc {
        raw_args.select { |arg|
          arg.match?(/^-[^-]/)
        }.flat_map { |arg|
          arg.sub(/^-/, '').chars
        }
      }.call
    end

    def flag?(flag)
      flags.include?(flag)
    end

    def flag_value(flag)
      found_flag = false
      raw_args.each do |arg|
        if found_flag
          return arg
        end

        if arg.match?(/^-\w*#{flag}/)
          found_flag = true
        end
      end

      nil
    end

    def values
      raw_args.reject do |arg|
        arg.match?(/^-/)
      end
    end
  end

  load_env
end
