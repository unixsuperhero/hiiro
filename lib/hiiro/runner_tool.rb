require 'yaml'
require 'json'
require 'time'
require 'fileutils'
require 'shellwords'

class Hiiro
  class RunnerTool
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'tools.yml')

    KNOWN_CHANGE_SETS = %w[dirty branch all].freeze
    KNOWN_TOOL_TYPES = %w[lint test format].freeze
    FILENAMES = '[FILENAMES]'
    PLACEHOLDER = /\[[A-Z_]+\]/

    def self.log_dir = Hiiro::Config.data_path('captures/validation')

    # The paths of one change set, enumerated in the repository that owns the
    # context's directory. Git failures raise; they never read as "no changes".
    class ChangeSet
      Change = Data.define(:path, :status, :from)

      STATUS = { 'A' => 'added', 'C' => 'copied', 'D' => 'deleted', 'M' => 'modified', 'R' => 'renamed',
                 'T' => 'modified', 'U' => 'unmerged' }.freeze

      attr_reader :name, :directory, :root, :changes

      def self.collect(name, directory:)
        directory = File.realpath(directory)
        git = Git::IndexGit.at(directory) or raise Hiiro::Error, "Not a git repository: #{directory}"
        listing = case name
        when 'dirty'
          base = git.head || git.empty_tree
          # add -A on a copy of the index lists untracked files and renames without staging anything.
          git.with_index_copy do |copy|
            git.run!('add', '-A', index: copy)
            git.run!('diff', '--cached', '--name-status', '-z', '-M', base, index: copy).stdout
          end
        when 'branch'
          base = git.run('merge-base', 'HEAD', 'main')
          raise Hiiro::Error, "No merge base between HEAD and main in #{git.root}" unless base.success?
          git.run!('diff', '--name-status', '-z', '-M', "#{base.stdout.chomp}...HEAD").stdout
        else
          raise Hiiro::Error, "Unknown change set: #{name}"
        end
        changes = Git::ChangeSet.name_status(listing).map do |status, path, from|
          Change.new(path: path, status: STATUS.fetch(status, status), from: from)
        end
        new(name, directory, File.realpath(git.root), changes)
      end

      def initialize(name, directory, root, changes)
        @name = name
        @directory = directory
        @root = root
        @changes = changes
      end

      def deleted = changes.select { |change| change.status == 'deleted' }

      # What tools receive: present paths under the directory, relative to it.
      # A rename contributes its destination; a deletion contributes nothing.
      def files
        prefix = directory + File::SEPARATOR
        changes.filter_map do |change|
          next if change.status == 'deleted'
          path = File.join(root, change.path)
          next unless (File.exist?(path) || File.symlink?(path)) && path.start_with?(prefix)
          path.delete_prefix(prefix)
        end
      end
    end

    # A tools.yml command: an argv array, or authored shell text that receives the
    # files as "$@". `[FILENAMES]` is an argv element of its own and expands to one
    # argument per file; a file starting with "-" is passed as "./-name" unless the
    # element before `[FILENAMES]` is "--".
    class Template
      def self.from(tool, value)
        unless value.is_a?(Hash) && (value.keys & %w[argv shell]).size == 1
          raise Hiiro::Error, "Tool #{tool}: a command is `argv: [...]` or `shell: TEXT`"
        end
        new(tool, argv: value['argv'], shell: value['shell'])
      end

      attr_reader :tool, :argv, :shell

      def initialize(tool, argv: nil, shell: nil)
        @tool = tool
        @argv = argv
        @shell = shell
        argv ? validate_argv! : validate_shell!
      end

      def spec(files, cwd:)
        files ||= []
        return CommandSpecification.shell(shell, args: files, cwd: cwd) if shell

        words = argv.each_with_index.flat_map do |word, index|
          next [word] unless word == FILENAMES
          terminated = index.positive? && argv[index - 1] == '--'
          files.map { |file| !terminated && file.start_with?('-') ? "./#{file}" : file }
        end
        CommandSpecification.new(*words, cwd: cwd)
      end

      private

      def validate_argv!
        unless argv.is_a?(Array) && !argv.empty? && argv.all?(String)
          raise Hiiro::Error, "Tool #{tool}: argv must be a non-empty list of strings"
        end
        raise Hiiro::Error, "Tool #{tool}: argv cannot start with #{FILENAMES}" if argv.first == FILENAMES
        raise Hiiro::Error, "Tool #{tool}: #{FILENAMES} may appear once" if argv.count(FILENAMES) > 1
        bad = argv.find { |word| word != FILENAMES && word.match?(PLACEHOLDER) }
        raise Hiiro::Error, "Tool #{tool}: unsupported template element #{bad.inspect}; #{FILENAMES} must be a whole argv element" if bad
      end

      def validate_shell!
        raise Hiiro::Error, "Tool #{tool}: shell text cannot be blank" unless shell.is_a?(String) && !shell.strip.empty?
        if shell.match?(PLACEHOLDER)
          raise Hiiro::Error, "Tool #{tool}: shell recipes receive files as \"$@\"; #{shell[PLACEHOLDER]} is not substituted into shell text"
        end
      end
    end

    # One tools.yml entry.
    class Definition
      attr_reader :name, :config

      def initialize(name, config)
        @name = name
        @config = config || {}
      end

      def variations = config['variations'] || {}
      def extensions = (config['file_extensions'] || '').to_s.split(',').map(&:strip).reject(&:empty?)

      # The pre-step-10 format: `command:` / variation strings spliced into shell text.
      def legacy? = config.key?('command') || variations.values.any?(String)

      def template(variation = nil)
        Template.from(name, variation ? variations.fetch(variation) : config.slice('argv', 'shell'))
      end

      def select(files)
        return files if files.nil? || extensions.empty?
        files.select { |file| extensions.include?(File.extname(file).delete('.')) }
      end
    end

    # The explicit tools.yml cutover from `command:` strings. A command made only
    # of plain words becomes argv; anything with shell syntax stays shell text with
    # each unquoted `[FILENAMES]` word replaced by "$@". Commands that cannot be
    # converted without changing their meaning are left for a manual edit.
    module LegacyConversion
      PLAIN_WORD = %r{\A[A-Za-z0-9_\-./:,+@%^]+\z}

      def self.convert(text)
        words = text.strip.split(/\s+/)
        return { 'argv' => words } if !words.empty? && words.first != FILENAMES && words.all? { |w| w == FILENAMES || w.match?(PLAIN_WORD) }

        shell = +''
        rest = text
        while (index = rest.index(FILENAMES))
          before = rest[0, index]
          after = rest[index + FILENAMES.length]
          quoted = (shell + before).count("'").odd? || (shell + before).count('"').odd?
          standalone = (before.empty? ? shell.empty? || shell.end_with?(' ') : before.match?(/\s\z/)) && (after.nil? || after.match?(/[\s;|&)]/))
          return nil if quoted || !standalone
          shell << before << '"$@"'
          rest = rest[(index + FILENAMES.length)..]
        end
        shell << rest
        shell.match?(PLACEHOLDER) ? nil : { 'shell' => shell }
      end

      # Returns [converted_config, report]; report rows are { tool:, variation:, from:, to: } (to nil = manual).
      def self.convert_config(configs)
        report = []
        converted = configs.to_h do |name, cfg|
          next [name, cfg] unless cfg.is_a?(Hash)
          cfg = cfg.each_with_object({}) do |(key, value), out|
            if key == 'command' && value.is_a?(String)
              to = convert(value)
              report << { tool: name, variation: nil, from: value, to: to }
              to ? out.merge!(to) : out[key] = value
            elsif key == 'variations' && value.is_a?(Hash)
              out[key] = value.to_h do |variation, command|
                next [variation, command] unless command.is_a?(String)
                to = convert(command)
                report << { tool: name, variation: variation, from: command, to: to }
                [variation, to || command]
              end
            else
              out[key] = value
            end
          end
          [name, cfg]
        end
        [converted, report]
      end
    end

    Step = Data.define(:name, :spec, :skip_reason)

    # One command's outcome: succeeded | failed | interrupted | skipped.
    StepResult = Data.define(:name, :status, :outcome, :log_path, :reason, :capture_id)

    # Runs steps in order. A failure does not stop later steps; an interrupt
    # stops the run and the remaining steps are skipped. Each command streams to
    # the terminal and its log; succeeded logs are deleted, the rest are kept as
    # Capture rows carrying the run id and the context's provenance.
    def self.execute(steps, context:, run_id: Capture.new_run_id, out: $stdout, err: $stderr, stdin: $stdin)
      results = []
      steps.each_with_index do |step, index|
        if results.any? { |result| result.status == 'interrupted' }
          results << StepResult.new(step.name, 'skipped', nil, nil, 'not run: interrupted', nil)
        elsif step.skip_reason
          results << StepResult.new(step.name, 'skipped', nil, nil, step.skip_reason, nil)
        else
          out.puts "==> #{step.name}: #{step.spec.preview}"
          out.flush
          path = File.join(log_dir, run_id, format('%02d-%s.log', index + 1, step.name.gsub(/[^A-Za-z0-9_.-]+/, '-')))
          recorded = Capture.record(step.spec, path: path, name: step.name, run_id: run_id, source: 'validation',
                                    context: context, retain: :failures, out: out, stdin: stdin, err: err)
          results << StepResult.new(step.name, recorded.status, recorded.outcome, recorded.path, recorded.error, recorded.capture&.id)
        end
      end
      report(results, run_id, out)
      exit_code(results)
    end

    # 130 when interrupted, else the first failed command's status, else 0.
    def self.exit_code(results)
      return 130 if results.any? { |result| result.status == 'interrupted' }

      failed = results.find { |result| result.status == 'failed' }
      failed ? failed.outcome.shell_code : 0
    end

    def self.report(results, run_id, out)
      counts = %w[failed interrupted succeeded skipped].filter_map do |status|
        n = results.count { |result| result.status == status }
        "#{n} #{status}" if n.positive?
      end
      out.puts "\n--- run #{run_id}: #{counts.join(', ')}"
      width = results.map { |result| result.name.length }.max.to_i
      results.each do |result|
        line = case result.status
        when 'succeeded' then "✓ #{result.name.ljust(width)}  #{result.outcome}"
        when 'skipped' then "- #{result.name.ljust(width)}  skipped: #{result.reason}"
        else "✗ #{result.name.ljust(width)}  #{result.status} (#{result.outcome})  log: #{result.log_path}"
        end
        out.puts line
      end
      if results.any? { |result| %w[failed interrupted].include?(result.status) }
        out.puts "Queue these failures for an agent: h run queue #{run_id}"
      end
      out.flush
    end

    # The queue prompt for one run's retained failures. Only `h run queue`
    # creates it, and queueing never launches an agent.
    class QueueJob
      attr_reader :run_id, :captures, :name, :content

      def self.latest_run_id
        row = Capture.where(source: 'validation').exclude(outcome: 'succeeded').order(Sequel.desc(:id)).first
        row&.run_id or raise Hiiro::Error, 'No retained validation failures'
      end

      def self.for_run(run_id)
        captures = Capture.where(source: 'validation', run_id: run_id).exclude(outcome: 'succeeded').order(:id).all
        raise Hiiro::Error, "No retained failures for run #{run_id}" if captures.empty?
        new(run_id, captures)
      end

      def initialize(run_id, captures)
        @run_id = run_id
        @captures = captures
        context = JSON.parse(captures.first.context_json || '{}')
        front = { 'validation_run' => run_id, 'task_name' => context['task'], 'app' => context['app'],
                  'dir' => relative_dir(context) }.compact
        @name = "validation-#{run_id}"
        @content = "#{YAML.dump(front)}---\n#{body(context)}"
      end

      private

      # The queue resolves dir against the task (or app) directory; a taskless
      # run keeps its absolute directory in the body only.
      def relative_dir(context)
        return nil unless context['task'] && context['directory']
        base = context['app_directory'] || context['root']
        return nil if base.nil? || context['directory'] == base
        dir = context['directory'].delete_prefix(base + File::SEPARATOR)
        dir == context['directory'] ? nil : dir
      end

      def body(context)
        lines = ["Validation run #{run_id} has #{captures.size} failed command#{captures.size == 1 ? '' : 's'}.", '']
        lines << "Task: #{context['task'] ? "#{context['task']} (#{context['task_source']})" : 'none'}"
        lines << "App: #{context['app']}" if context['app']
        lines << "Root: #{context['root']} (#{context['root_source']})" if context['root']
        lines << "Directory: #{context['directory']} (#{context['directory_source']})" if context['directory']
        lines << ''
        captures.each do |capture|
          outcome = capture.exit_signal ? "signal #{capture.exit_signal}" : "exit #{capture.exit_status}"
          lines << "- #{capture.name}: #{capture.outcome} (#{outcome})"
          lines << "  command: #{capture.command}"
          lines << "  cwd: #{capture.cwd}"
          lines << "  log: #{capture.path}"
          lines << "  ran: #{capture.started_at} .. #{capture.finished_at}"
        end
        lines << ''
        lines << 'Read each log, fix the cause, and re-run the same commands in the same directory to confirm.'
        lines.join("\n")
      end
    end

    attr_reader :config_file
    attr_writer :context

    def initialize(config_file: CONFIG_FILE, context: nil)
      @config_file = config_file
      @context = context
    end

    # A callable context (the root `h` mounts pass one) resolves on first use, so help needs no task.
    def context
      @context = @context.call if @context.respond_to?(:call)
      @context ||= CurrentTask.new(pin: false).context
    end

    def tools
      load_config
    end

    def find_tool(name)
      raise Hiiro::Error, 'Tool name is required' if name.to_s.strip.empty?
      configs = tools
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      raise Hiiro::Error, "Ambiguous tool '#{name}'" if !result.resolved && result.matches.size > 1
      match = result.resolved
      return nil unless match

      tool_name = match.item.name
      { name: tool_name, **symbolize_keys(configs[tool_name]) }
    end

    def find_tools(tool_type: nil, file_type_group: nil)
      configs = tools
      configs.select { |_, cfg|
        (tool_type.nil? || cfg['tool_type'] == tool_type) &&
          (file_type_group.nil? || cfg['file_type_group'] == file_type_group)
      }
    end

    # Builds every selected step before anything runs, so a bad definition,
    # variation, or Git failure stops the run with nothing executed.
    def steps(change_set: 'dirty', tool_type: nil, file_type_group: nil, variation: nil, out: $stdout)
      definitions = find_tools(tool_type: tool_type, file_type_group: file_type_group).map { |name, cfg| Definition.new(name, cfg) }
      if definitions.empty?
        raise Hiiro::Error, "No tools match tool_type #{tool_type || '(any)'}, file_type_group #{file_type_group || '(any)'}"
      end
      legacy = definitions.select(&:legacy?)
      unless legacy.empty?
        raise Hiiro::Error, "#{config_file} uses the old `command:` format (#{legacy.map(&:name).join(', ')}); run `h run migrate` to convert it"
      end
      if variation && definitions.none? { |definition| definition.variations.key?(variation) }
        raise Hiiro::Error, "Unknown variation '#{variation}' for #{definitions.map(&:name).join(', ')}"
      end

      context.validate!
      directory = context.start_directory
      files = nil
      unless change_set == 'all'
        changes = ChangeSet.collect(change_set, directory: directory)
        files = changes.files
        skipped = changes.deleted.size
        out.puts "#{change_set}: #{files.size} file#{files.size == 1 ? '' : 's'} under #{directory}#{skipped.positive? ? " (#{skipped} deleted, not passed)" : ''}"
      end

      definitions.map do |definition|
        if variation && !definition.variations.key?(variation)
          next Step.new(definition.name, nil, "no variation '#{variation}'")
        end
        template = definition.template(variation)
        tool_files = definition.select(files)
        if files && tool_files.empty?
          next Step.new(definition.name, nil, "no matching files (#{definition.extensions.join(',')})")
        end
        Step.new(definition.name, template.spec(tool_files, cwd: directory), nil)
      end
    end

    # Returns the aggregate exit status (see .exit_code).
    def run(out: $stdout, err: $stderr, stdin: $stdin, **selection)
      self.class.execute(steps(out: out, **selection), context: context, out: out, err: err, stdin: stdin)
    end

    # Rewrites tools.yml from the old `command:` format, keeping a backup of the
    # original. Returns the report rows.
    def migrate_config!
      raise Hiiro::Error, "No tools file at #{config_file}" unless File.exist?(config_file)
      converted, report = LegacyConversion.convert_config(load_config)
      return report if report.empty?

      backup = "#{config_file}.#{Time.now.strftime('%Y%m%d%H%M%S')}.bak"
      raise Hiiro::Error, "Backup already exists: #{backup}" if File.exist?(backup)
      FileUtils.cp(config_file, backup, preserve: true)
      save_config(converted)
      report.map { |row| row.merge(backup: backup) }
    end

    def add_tool(config_hash)
      name = config_hash.delete('name') || config_hash.delete(:name)
      unless name
        puts "Tool name required"
        return false
      end

      configs = load_config
      if configs.key?(name)
        puts "Tool '#{name}' already exists"
        return false
      end

      configs[name] = config_hash.transform_keys(&:to_s)
      save_config(configs)
      puts "Added tool '#{name}'"
      true
    end

    def remove_tool(name)
      configs = load_config
      unless configs.key?(name)
        puts "Tool '#{name}' not found"
        return false
      end

      configs.delete(name)
      save_config(configs)
      puts "Removed tool '#{name}'"
      true
    end

    def self.build_hiiro(parent_hiiro, rt, context: parent_hiiro.context, args: parent_hiiro.args)
      rt.context = context
      parent_hiiro.make_child(:run, args, context: -> { rt.context }) do |h|
        h.add_default do |*run_args|
          change_set = nil
          tool_type = nil
          file_type_group = nil
          variation = nil

          positional = []
          args_iter = run_args.each
          loop do
            arg = args_iter.next
            case arg
            when '--variation', '-v'
              variation = args_iter.next
            else
              positional << arg
            end
          end

          positional.each do |arg|
            if KNOWN_CHANGE_SETS.include?(arg)
              change_set = arg
            elsif KNOWN_TOOL_TYPES.include?(arg)
              tool_type = arg
            else
              # Treat as file_type_group
              file_type_group ||= arg
            end
          end

          change_set ||= 'dirty'

          exit rt.run(
            change_set: change_set,
            tool_type: tool_type,
            file_type_group: file_type_group,
            variation: variation,
          )
        end

        h.add_subcmd(:ls) do
          configs = rt.tools
          if configs.empty?
            puts "No tools configured."
            puts "Use 'run add' to add one, or edit #{rt.config_file}"
            next
          end

          puts "Configured tools:"
          puts
          configs.each do |name, cfg|
            variations = cfg['variations'] ? " (#{cfg['variations'].keys.join(', ')})" : ""
            puts format("  %-15s  [%s]  %-10s  exts: %s%s",
              name,
              cfg['tool_type'] || '?',
              cfg['file_type_group'] || '?',
              cfg['file_extensions'] || '*',
              variations)
          end
        end

        h.add_subcmd(:add) do |*add_args|
          template = {
            'tool_type' => 'lint',
            'argv' => ['echo', FILENAMES],
            'variations' => {},
            'file_type_group' => '',
            'file_extensions' => '',
          }

          input = InputFile.yaml_file(hiiro: h, content: YAML.dump({ 'new_tool' => template }), prefix: 'tool')
          input.edit

          begin
            data = input.parsed_file(permitted_classes: [Symbol]) || {}
            data.each do |name, cfg|
              rt.add_tool({ 'name' => name }.merge(cfg || {}))
            end
          rescue => e
            puts "Error parsing config: #{e.message}"
          ensure
            input.cleanup
          end
        end

        h.add_subcmd(:rm) do |tool_name=nil|
          unless tool_name
            puts "Usage: run rm <name>"
            next
          end

          rt.remove_tool(tool_name)
        end

        h.add_subcmd(:config) do
          h.edit_files(rt.config_file)
        end

        h.add_subcmd(:migrate) do
          report = rt.migrate_config!
          if report.empty?
            puts "#{rt.config_file} has no `command:` entries; nothing to convert."
            next
          end
          report.each do |row|
            label = row[:variation] ? "#{row[:tool]} (variation #{row[:variation]})" : row[:tool]
            puts "#{label}: #{row[:from]}"
            puts row[:to] ? "  -> #{row[:to].to_json}" : '  -> left as is: edit it by hand (argv: or shell: with "$@")'
          end
          puts "Backup: #{report.first[:backup]}"
          exit(report.all? { |row| row[:to] } ? 0 : 1)
        end

        h.add_subcmd(:queue) do |run_id = nil|
          job = QueueJob.for_run(run_id || QueueJob.latest_run_id)
          added = Queue.current(nil, context: rt.context).add_with_frontmatter(job.content, name: job.name)
          puts "Queued #{added[:name]}: #{added[:path]}"
        end
      end
    end

    private

    def load_config
      return {} unless File.exist?(config_file)
      YAML.safe_load_file(config_file, permitted_classes: [Symbol]) || {}
    end

    def save_config(data)
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, YAML.dump(data))
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end
end
