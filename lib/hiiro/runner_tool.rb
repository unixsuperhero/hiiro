require 'yaml'
require 'fileutils'
require 'shellwords'

class Hiiro
  class RunnerTool
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'tools.yml')

    KNOWN_CHANGE_SETS = %w[dirty branch all].freeze
    KNOWN_TOOL_TYPES = %w[lint test format].freeze

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

    def changed_files(change_set, git: nil)
      git ||= Hiiro::Git.new(nil, context.start_directory)
      files = case change_set
      when 'dirty'
        git.dirty_files
      when 'branch'
        base = git.merge_base('HEAD', 'main') || 'main'
        git.changed_files("#{base}...HEAD", relative: false).map { |file| File.expand_path(file, git.root || git.pwd) }
      when 'all'
        return nil
      else
        return nil
      end
      directory = File.realpath(context.start_directory)
      files.filter_map do |file|
        path = File.expand_path(file)
        next unless path.start_with?(directory + File::SEPARATOR)
        path.delete_prefix(directory + File::SEPARATOR)
      end
    end

    def run(change_set: 'dirty', tool_type: nil, file_type_group: nil, variation: nil, git: nil)
      matching = find_tools(tool_type: tool_type, file_type_group: file_type_group)

      if matching.empty?
        puts "No tools found matching criteria"
        puts "  tool_type: #{tool_type || '(any)'}"
        puts "  file_type_group: #{file_type_group || '(any)'}"
        return false
      end

      context.validate!
      files = changed_files(change_set, git: git)

      matching.each do |name, cfg|
        tool_files = filter_files_for_tool(files, cfg)

        if files && tool_files.empty?
          puts "No matching files for '#{name}' (#{cfg['file_extensions']})"
          next
        end

        cmd = if variation && cfg['variations'] && cfg['variations'][variation]
          cfg['variations'][variation]
        else
          cfg['command']
        end

        filenames = tool_files ? Shellwords.join(tool_files) : ''
        cmd = cmd.gsub('[FILENAMES]') { filenames }

        puts "Running #{name}: #{cmd}"
        system(cmd, chdir: context.start_directory)
      end

      true
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

    def self.build_hiiro(parent_hiiro, rt, git: nil, context: parent_hiiro.context, args: parent_hiiro.args)
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

          rt.run(
            change_set: change_set,
            tool_type: tool_type,
            file_type_group: file_type_group,
            variation: variation,
            git: git,
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
            'command' => 'echo [FILENAMES]',
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

    def filter_files_for_tool(files, cfg)
      return files unless files

      extensions = (cfg['file_extensions'] || '').split(',').map(&:strip)
      return files if extensions.empty?

      files.select { |f|
        ext = File.extname(f).delete('.')
        extensions.include?(ext)
      }
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end
end
