require "fileutils"
require "yaml"
require "json"
require "time"
require "open3"
require "set"
require "shellwords"
require "pry"
require "ostruct"
require 'awesome_print'

require_relative "hiiro/version"
require_relative "hiiro/error"
require_relative "hiiro/config"
require_relative "hiiro/bins"
require_relative "hiiro/matcher"
require_relative "hiiro/options"
require_relative "hiiro/catalog"
require_relative "hiiro/runtime"

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
  REPO_PATH = File.join(WORK_DIR, '.git')

  # Domain constants load on first reference so that importing the framework,
  # registering commands, help, and discovery touch no database or config.
  # Persistent models load together through hiiro/persistence, which starts the
  # runtime (see Hiiro::Runtime).
  DOMAIN = {
    'alias_editor' => %i[AliasEditor], 'any_struct' => %i[AnyStruct], 'app_files' => %i[AppFiles], 'artifact' => %i[Artifact],
    'clipboard' => %i[Clipboard], 'context_bundle' => %i[ContextBundle], 'selection' => %i[Selection],
    'background' => %i[Background], 'check_summary' => %i[CheckContext CheckSummary],
    'current_task' => %i[CurrentTask], 'duration' => %i[Duration], 'effects' => %i[Effects],
    'extractor' => %i[Extractor], 'fuzzyfind' => %i[Fuzzyfind], 'git' => %i[Git], 'glob' => %i[Glob],
    'herdr' => %i[Herdr], 'input_file' => %i[EditedDocument InputFile], 'install' => %i[Install], 'notification' => %i[Notification],
    'owned_run' => %i[OwnedRun], 'job_screen' => %i[JobScreen], 'pane_reservations' => %i[PaneReservations], 'paths' => %i[Paths],
    'path_pattern' => %i[PathPattern], 'picker' => %i[Picker], 'picker_screen' => %i[PickerScreen],
    'pinned_pr_manager' => %i[PinnedPRManager], 'pr_actions' => %i[PrActions PrFixJob], 'pr_monitor' => %i[PrMonitor], 'pr_snapshot' => %i[PrSnapshot], 'projects' => %i[Projects], 'ps_process' => %i[PsProcess],
    'pull_request_reference' => %i[RepositoryIdentity PullRequestReference], 'queue' => %i[Queue],
    'queue_claim' => %i[QueueClaim], 'rbenv' => %i[Rbenv], 'root_commands' => %i[RootCommands], 'rollout' => %i[Rollout], 'runner_tool' => %i[RunnerTool],
    'service_definition' => %i[ServiceDefinition ServiceGroup EnvironmentFile],
    'service_manager' => %i[ServiceManager], 'shell' => %i[CommandSpecification ProcessOutcome Shell Result],
    'table' => %i[Table], 'table_actions' => %i[TableActions], 'table_scope' => %i[TableScope],
    'task_cli' => %i[TaskCli], 'task_location' => %i[TaskLocation], 'task_sessions' => %i[TaskSessions],
    'tasks' => %i[TaskManager SparseGroups Tasks Tree Task FallbackTarget App Environment],
    'time_input' => %i[TimeInput], 'tui' => %i[Tui], 'tuios' => %i[Tuios],
    'profile' => %i[Profile], 'time_commands' => %i[TimeCommands], 'codec' => %i[Codec],
    'environment_assignment' => %i[EnvironmentAssignment], 'text_inspection' => %i[TextInspection],
    'media' => %i[Media], 'cast' => %i[Cast], 'screen_capture' => %i[ScreenCapture],
    'directory_profile' => %i[DirectoryProfile], 'commit_log' => %i[CommitLog],
    'persistence' => %i[DB AppRecord Assignment Branch Capture CheckRun Invocation InvocationResolution Link
                        URLTemplate PaneHome PinRecord PinnedPr PrMonitorCheckpoint Project RegistryEntry Reminder Tag Tags
                        TaskRecord TaskResource TodoItem TodoManager Job JobClaim JobOutcome Schedule ScheduleCheckpoint
                        PickerExclusion]
  }.freeze
  DOMAIN.each { |file, names| names.each { |name| autoload name, File.expand_path("hiiro/#{file}", __dir__) } }

  def self.init(*oargs, plugins: [], logging: false, tasks: false, task_scope: nil, builtin_commands: true, **values, &block)
    h_bin = values[:bin_name] || $0
    h_args = oargs
    h_args = ARGV if h_args.empty?
    h_args = values[:args] if values.key?(:args)

    new(h_bin, *h_args, logging: logging, tasks: tasks, task_scope: task_scope, **values).tap do |hiiro|
      Runtime.track(hiiro)
      hiiro.load_plugins(plugins)
      hiiro.register_builtins if builtin_commands

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

  def self.run(*args, plugins: [], logging: false, tasks: false, task_scope: nil, builtin_commands: true, **values, &block)
    hiiro = init(*args, plugins:, logging:, tasks:, task_scope:, builtin_commands:, **values, &block)

    hiiro.run
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

  def context
    return @context if defined?(@context)
    supplied = global_values[:context]
    @context = if supplied
      supplied.respond_to?(:call) ? supplied.call : supplied
    else
      CurrentTask.new(herdr: -> { herdr_client }, cwd: global_values[:cwd] || Dir.pwd, pin: false,
                      chooser: Picker.task_chooser(hiiro: self)).context
    end
  end

  def environment
    @environment ||= Environment.new(path: global_values[:cwd] || Dir.pwd, context: @context || global_values[:context] || -> { context }, chooser: method(:fuzzyfind_from_map))
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
    ENV['EDITOR'] || %w[nvim vim vi].lazy.filter_map { |name| Bins.which(name) }.first
  end

  def vim?
    editor.to_s.match?(/vim/i)
  end

  def yaml_input_file(content: nil, append: false, prefix: 'edit-')
    InputFile.yaml_file(hiiro: self, content:, append:, prefix:)
  end

  def md_input_file(content: nil, append: false, prefix: 'edit-')
    InputFile.md_file(hiiro: self, content:, append:, prefix:)
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

  def open_config(file, dir: nil)
    Hiiro::Config.open(file, dir: dir)
  end

  # Open a file, directory, or URL with the OS default handler.
  def open_default(target)
    executable = RUBY_PLATFORM.include?('darwin') ? 'open' : 'xdg-open'
    system(executable, target)
  end

  def herdr_client
    @herdr_client ||= Herdr.client!(self)
  end

  def start_herdr_workspace(name, **opts)
    herdr_client.open_workspace(name, **opts)
  end

  def make_child(custom_subcmd=nil, custom_args=nil, **kwargs, &block)
    child_subcmd = custom_subcmd || subcmd
    child_args = custom_args || args

    child_bin_name = [bin, child_subcmd.to_s].join(?-)

    parent_resolvers = @resolvers&.dup

    wrapper = lambda do |h|
      h.instance_variable_set(:@resolvers, parent_resolvers.dup) if parent_resolvers
      block.arity == 1 ? block.call(h) : h.instance_eval(&block) if block
    end

    inherited = global_values.except(:bin_name, :args).merge(context: -> { context })
    Hiiro.init(bin_name: child_bin_name, args: child_args, **inherited, **kwargs, &wrapper)
  end

  def run_child(custom_subcmd=nil, custom_args=nil, **kwargs, &block)
    make_child(custom_subcmd, custom_args, **kwargs, &block).run
  end

  def todo_manager
    @todo_manager ||= TodoManager.new
  end

  def queue
    @queue ||= Queue.current
  end

  def run
    run_args = runners.using_default? ? [subcmd, *args].compact : args
    result = runner.run(*run_args)

    handle_result(result)

    exit 1
  rescue Hiiro::Error => e
    abort "ERROR: #{e.message}"
  rescue => e
    puts "ERROR: #{e.message}"
    puts e.backtrace
    exit 1
  end

  def handle_result(result)
    return result if result.is_a?(Integer)
    exit 0 if result.nil? || result

    exit 1
  end

  def auto_tag_branch_with_task
    task = environment.task
    return unless task

    branch = environment.tree&.branch
    return if branch.nil? || branch.empty?
    return if %w[master main].include?(branch)

    tag_store = Tags.new(:branch)
    return if tag_store.get(branch).include?(task.name)

    tag_store.add(branch, task.name)
  rescue
    # never let auto-tagging break a command
  end

  def runnable?
    runner
  end

  def runner
    runners.runner
  end

  def catalog
    runners.catalog
  end

  def register_builtins
    add_subcommand(:pry) { |*| binding.pry }
    add_subcommand(:edit) { |*names| edit_commands(*names) }
  end

  # The bin itself with no names; otherwise the source dispatch would run for each name.
  def edit_commands(*names)
    return edit_files(bin) if names.empty?

    sources = names.map do |name|
      resolution = catalog.resolve(name)
      entry = resolution.entry if resolution.resolved?
      unless entry
        found = resolution.candidates
        raise Hiiro::Error, "No #{bin_name} command matches #{name.inspect}" if found.empty?
        raise Hiiro::Error, "Ambiguous #{bin_name} command #{name.inspect}: #{found.map(&:name).join(', ')}" unless $stdin.tty?

        entry = Picker.choose("#{bin_name}-commands", found.map { |candidate| Picker.command_item(candidate) },
                              family: :command, hiiro: self)&.value
        raise Hiiro::Error, 'No command selected' unless entry
      end
      entry.source.sub(/:\d+\z/, '')
    end
    sources.uniq.each { |source| warn "editing #{source} (#{catalog.origin(source)})" }
    edit_files(*sources.uniq)
  end

  def invocation_frame
    { bin: File.basename(bin), subcmd: all_args.first, args: all_args[1..] || [] }
  end

  # Pick a registry entry with the shared picker. Returns the canonical name string, or nil.
  # Usage inside a subcommand block:
  #   task = opts.task || registry_pick('isc_task')
  def registry_pick(type = nil)
    entries = type ? Hiiro::RegistryEntry.of_type(type) : Hiiro::RegistryEntry.all_ordered
    return nil if entries.empty?

    Hiiro::RegistryEntry.pick(entries, type: type, hiiro: self)&.name
  end

  def runners
    @runners ||= Runners.new(self)
  end

  def add_default(**values, &handler)
    runners.add_default(handler, **global_values, **values)
  end

  def add_subcommand(*names, opts: nil, **values, &handler)
    name, *aliases = names
    runners.add_subcommand(name, handler, aliases:, opts: opts, **global_values, **values)
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

  def tuios = @tuios ||= Hiiro::Tuios.new

  def add_cmd(*names, args: [], opts: [], passthrough: false, &block)
    cmd_opts = options.select(opts)

    wrapper = lambda do |*raw_args|
      next instance_eval(&block) if passthrough
      @opts = cmd_opts.parse(raw_args)
      if @opts.help?
        puts @opts.help_text
        next
      end
      instance_eval(&block)
    end

    name, *aliases = names
    runners.add_subcommand(
      name, wrapper,
      aliases:,
      subcmd_args: args,
      subcmd_opts: cmd_opts,
      **global_values,
      source_location: block.source_location&.join(':')
    )
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
    @git ||= Git.new(self, context.start_directory)
  end

  def attach_method(name, &block)
    define_singleton_method(name.to_sym, &block)
  end

  def load_plugins(*plugins)
    plugins.flatten.each { |plugin| load_plugin(plugin) }
  end

  # A plugin named by String/Symbol is required from its file (user plugin
  # directory first, then the gem's plugins/) only when a bin asks for it.
  def load_plugin(plugin_const)
    if plugin_const.is_a?(String) || plugin_const.is_a?(Symbol)
      begin
        name = plugin_const.to_s
        file = Config.plugin_file(name) unless Object.const_defined?(name)
        require file if file
        plugin_const = Object.const_get(name)
      rescue NameError, LoadError => e
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
    resolution = runners.resolution

    puts "Current command: #{bin_name}!"

    if resolution.ambiguous?
      puts "Ambiguous subcommand #{subcmd.inspect}!"
      puts
      puts "Did you mean one of these?"
      list_runners(resolution.candidates)
      puts
    else
      puts "Subcommand required for #{bin_name}"
      puts
      puts "Possible subcommands:"
      list_runners(catalog.entries)
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

  # entries: Catalog::Entry list. Aliases follow the name; shadowed claims follow the row.
  def list_runners(entries)
    sorted = entries.sort_by(&:name)
    vars = build_location_vars(sorted.flat_map { |e| [e.source, *e.shadowed.map(&:source)] })

    vars.each { |var_name, path| puts "export #{var_name}=\"#{path}\"" }
    puts if vars.any?

    names      = sorted.map { |e| [e.name, *e.aliases].join(', ') }
    max_name   = names.map(&:length).max || 0
    max_type   = sorted.map { |e| e.kind.to_s.length }.max || 0
    max_params = sorted.map { |e| e.arguments.length }.max || 0

    sorted.each_with_index do |e, i|
      type       = "(#{e.kind})".ljust(max_type + 2)
      location   = shorten_location(e.source, vars)
      location  += "  [#{catalog.origin(e.source)}]" if e.kind == :external
      puts "  #{names[i].ljust(max_name)}  #{e.arguments.ljust(max_params)}  #{type}  #{location}"
      e.shadowed.each do |claim|
        label = claim.alias_of ? "alias #{claim.name} of #{claim.alias_of}" : claim.kind
        origin = claim.kind == 'external' ? "  [#{catalog.origin(claim.source)}]" : ''
        puts "  #{' ' * max_name}  shadows #{label} #{shorten_location(claim.source, vars)}#{origin}"
      end
    end
  end

  def build_location_vars(locations)
    paths = locations.compact.map { |loc| loc.sub(/:\d+$/, '') }
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
      subgroups = dirs.group_by do |dir|
        depth = lca_depth + (dir.start_with?('/') ? 2 : 1)
        dir.split('/').first(depth).join('/')
      end
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

  # Registrations of one Hiiro instance. Resolution goes through its Catalog.
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
        values
      )
    end

    def catalog
      @catalog ||= Catalog.new(bin_name, inline: subcommands.values,
                                         external: hiiro.global_values.fetch(:external_commands, true))
    end

    def resolution
      @resolution ||= catalog.resolve(subcmd)
    end

    def runner
      resolution.resolved? ? resolution.entry.runner : @default_subcommand
    end

    def using_default?
      !resolution.resolved?
    end

    def subcommand_names
      catalog.entries.map(&:name)
    end

    def add_subcommand(name, handler, aliases: [], opts: nil, subcmd_args: [], subcmd_opts: nil, **values)
      @catalog = @resolution = nil
      @subcommands[name.to_s] = Subcommand.new(
        bin_name, name, handler, values,
        aliases: aliases,
        opts: opts,
        subcmd_args: subcmd_args,
        subcmd_opts: subcmd_opts
      )
    end

    # Inline only, by name or alias; external executables are not run from here.
    def run_subcommand(name, *args)
      cmd = subcommands[name.to_s] || subcommands.values.find { |sub| sub.aliases.include?(name.to_s) }

      cmd&.run(*args)
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

      def subcommand_name
        name.delete_prefix("#{bin_name}-")
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
      attr_reader :bin_name, :name, :handler, :values, :aliases, :opts, :subcmd_args, :subcmd_opts
      alias subcommand_name name

      def initialize(bin_name, name, handler, values={}, aliases: [], opts: nil, subcmd_args: [], subcmd_opts: nil)
        @bin_name = bin_name
        @name = name.to_s
        @handler = handler
        @values = values || {}
        @aliases = aliases.map(&:to_s)
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

      def full_name
        [bin_name, name].join(?-)
      end

      def type
        :subcommand
      end

      def location
        values[:source_location] || handler.source_location&.join(':')
      end

      def params_string
        if subcmd_args.any?
          return subcmd_args.map { |a| "<#{a}>" }.join(' ')
        end
        return nil if subcmd_opts

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
        subcmd_opts&.hint
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

end
