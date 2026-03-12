require "fileutils"
require "yaml"
require "shellwords"
require "pry"
require "ostruct"

require_relative "hiiro/version"
require_relative "hiiro/config"
require_relative "hiiro/bins"
require_relative "hiiro/fuzzyfind"
require_relative "hiiro/git"
require_relative "hiiro/glob"
require_relative "hiiro/matcher"
require_relative "hiiro/notification"
require_relative "hiiro/options"
require_relative "hiiro/paths"
require_relative "hiiro/queue"
require_relative "hiiro/tasks"
require_relative "hiiro/tmux"
require_relative "hiiro/todo"
require_relative "hiiro/service_manager"
require_relative "hiiro/runner_tool"
require_relative "hiiro/app_files"

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
        hiiro.edit_files(hiiro.bin)
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

  def self.options(&block)
    Options.setup(&block)
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
  attr_reader :opts

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

  def this
    self
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

  def editor
    editors = Bins.glob(%w[nvim vim vi]).find(&File.method(:executable?))

    ENV['EDITOR'] || editors.first
  end

  def vim?
    editor.to_s.match?(/vim/i)
  end

  def edit_files(*files, max_splits: 3)
    if editor.match?(/vim/i)
      if files.count > max_splits.to_i
        system(editor, '-O' + max_splits.to_i.to_s, *files)
      else
        system(editor, '-O', *files)
      end
    else
      system(editor, *files)
    end
  end

  def tmux_client
    @tmux_client ||= Tmux.client!(self)
  end

  def start_tmux_session(name, **opts)
    tmux_client.open_session(name, **opts)
  end

  def make_child(custom_subcmd=nil, custom_args=nil, **kwargs, &block)
    child_subcmd = custom_subcmd || subcmd
    child_args = custom_args || args

    child_bin_name = [bin, child_subcmd.to_s].join(?-)

    Hiiro.init(bin_name: child_bin_name, args: child_args, **kwargs, &block)
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

  def add_subcommand(*names, opts: nil, **values, &handler)
    names.each do |name|
      runners.add_subcommand(name, handler, opts: opts, **global_values, **values)
    end
  end
  alias add_subcmd add_subcommand

  def options
    @options ||= Hiiro::Options.setup {}
  end

  def add_option(name, **kwargs)
    options.option(name, **kwargs)
  end

  def add_flag(name, **kwargs)
    options.flag(name, **kwargs)
  end

  def add_cmd(*names, args: [], opts: [], &block)
    cmd_opts = options.select(opts)

    wrapper = lambda do |*raw_args|
      @opts = cmd_opts.parse(raw_args)
      instance_eval(&block)
    end

    names.each do |name|
      runners.add_subcommand(
        name, wrapper,
        subcmd_args: args,
        subcmd_opts: cmd_opts,
        **global_values
      )
    end
  end

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

    global = @options
    if global && global.definitions.any? { |k, _| k != :help }
      puts "Options:"
      puts global.help_text
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
    sorted = list.sort_by(&:subcommand_name)
    vars = build_location_vars(sorted)

    vars.each { |var_name, path| puts "export #{var_name}=\"#{path}\"" }
    puts if vars.any?

    max_name   = sorted.map { |r| r.subcommand_name.length }.max || 0
    max_type   = sorted.map { |r| r.type.to_s.length }.max || 0
    max_params = sorted.map { |r| r.params_string.to_s.length }.max || 0

    sorted.each do |r|
      name       = r.subcommand_name.ljust(max_name)
      type       = "(#{r.type})".ljust(max_type + 2)
      params     = r.params_string
      params_col = params ? params.ljust(max_params) : ''.ljust(max_params)
      location   = shorten_location(r.location, vars)
      hint       = r.respond_to?(:opts_hint) ? r.opts_hint : nil
      hint_col   = hint && !hint.empty? ? "  #{hint}" : ""
      puts "  #{name}  #{params_col}  #{type}  #{location}#{hint_col}"
    end
  end

  def build_location_vars(list)
    paths = list.map { |r| r.location }.compact.map { |loc| loc.sub(/:\d+$/, '') }
    dirs  = paths.map { |p| File.dirname(p) }.uniq

    ancestors = consolidate_dirs(dirs, min_depth: 4)

    vars = {}
    ancestors.sort.each do |ancestor|
      name = auto_var_name(ancestor, vars)
      vars[name] = ancestor
    end
    vars
  end

  # Recursively group directories under their common ancestor when that
  # ancestor is deep enough to be a useful alias (>= min_depth components).
  def consolidate_dirs(dirs, min_depth:)
    return dirs if dirs.length <= 1

    lca       = dirs.reduce { |a, b| path_lca(a, b) }
    lca_depth = lca.delete_prefix('/').split('/').reject(&:empty?).length

    if lca_depth >= min_depth
      [lca]
    else
      lca_parts = lca.split('/')
      subgroups = dirs.group_by { |d| d.split('/').first(lca_parts.length + 1).join('/') }
      subgroups.flat_map { |_, group| consolidate_dirs(group, min_depth: min_depth) }.uniq
    end
  end

  def path_lca(a, b)
    a_parts = a.split('/')
    b_parts = b.split('/')
    a_parts.zip(b_parts).take_while { |x, y| x == y }.map(&:first).join('/')
  end

  def auto_var_name(path, existing_vars)
    parts = path.delete_prefix('/').split('/')
    (1..parts.length).each do |n|
      candidate = parts.last(n).join('_').upcase.gsub(/[^A-Z0-9]/, '_').squeeze('_').delete_prefix('_').delete_suffix('_')
      return candidate unless existing_vars.key?(candidate)
    end
    "DIR_#{existing_vars.length + 1}"
  end

  def shorten_location(loc, vars)
    return loc if loc.nil?
    vars.sort_by { |_, path| -path.length }.each do |var_name, path|
      return loc.sub(path, "$#{var_name}") if loc.start_with?(path + '/') || loc == path
    end
    loc
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

    def add_subcommand(name, handler, opts: nil, subcmd_args: [], subcmd_opts: nil, **values)
      @subcommands[name] = Subcommand.new(
        bin_name, name, handler, values,
        opts: opts,
        subcmd_args: subcmd_args,
        subcmd_opts: subcmd_opts
      )
    end

    def run_subcommand(name, *args)
      cmd = subcommands[name]

      cmd&.run(*args)
    end

    def subcmd_result
      return nil unless subcmd
      @subcmd_result ||= Matcher.by_prefix(all_runners, subcmd.to_s, key: :subcommand_name)
    end

    def exact_runner
      subcmd_result&.exact_match&.item
    end

    def unambiguous_runner
      return nil unless subcmd_result
      matches = matching_runners
      matches.first if matches.count == 1
    end

    def ambiguous_matches
      return [] unless subcmd_result
      matches = matching_runners
      matches.count > 1 ? matches : []
    end

    def matching_runners
      return [] unless subcmd_result
      remove_child_runners(subcmd_result.matches.map(&:item))
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
      attr_reader :bin_name, :name, :handler, :values, :opts, :subcmd_args, :subcmd_opts
      alias subcommand_name name

      def initialize(bin_name, name, handler, values={}, opts: nil, subcmd_args: [], subcmd_opts: nil)
        @bin_name = bin_name
        @name = name.to_s
        @handler = handler
        @values = values || {}
        @opts = opts
        @subcmd_args = subcmd_args || []
        @subcmd_opts = subcmd_opts
      end

      def run(*args)
        if opts
          parsed = opts.parse(args)
          handler.call(parsed)
        else
          handler.call(*args)
        end
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
        if subcmd_args.any?
          return subcmd_args.map { |a| "<#{a}>" }.join(' ')
        end

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

      def opts_hint
        return nil unless subcmd_opts
        subcmd_opts.definitions
          .reject { |k, _| k == :help }
          .map { |_, d| d.flag? ? d.long_form : "#{d.long_form} <val>" }
          .map { |s| "[#{s}]" }
          .join(' ')
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
