require 'yaml'
require 'fileutils'
require_relative 'base_commands'
require_relative 'runner/commands'

class Hiiro
  class RunnerTool
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'tools.yml')

    KNOWN_CHANGE_SETS = %w[dirty branch all].freeze
    KNOWN_TOOL_TYPES = %w[lint test format].freeze

    attr_reader :config_file

    def initialize(config_file: CONFIG_FILE)
      @config_file = config_file
    end

    def tools
      load_config
    end

    def find_tool(name)
      configs = tools
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      match = result.resolved || result.first
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
      case change_set
      when 'dirty'
        output = `git status --porcelain 2>/dev/null`
        output.lines.map { |l| l.strip.sub(/^.{3}/, '') }.reject(&:empty?)
      when 'branch'
        base = `git merge-base HEAD main 2>/dev/null`.chomp
        base = 'main' if base.empty?
        output = `git diff --name-only #{base}...HEAD 2>/dev/null`
        output.lines.map(&:chomp).reject(&:empty?)
      when 'all'
        nil
      else
        nil
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

        filenames = tool_files ? tool_files.join(' ') : ''
        cmd = cmd.gsub('[FILENAMES]', filenames)

        puts "Running #{name}: #{cmd}"
        system(cmd)
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

    def edit_config
      editor = ENV['EDITOR'] || 'nvim'
      system(editor, config_file)
    end

    # Build a Hiiro command interface for runner operations.
    #
    # @param parent_hiiro [Hiiro] parent Hiiro instance
    # @param rt [RunnerTool] runner tool instance
    # @param git [Object, nil] optional git instance
    # @return [Hiiro] configured child Hiiro instance
    def self.build_hiiro(parent_hiiro, rt, git: nil)
      Commands.new(rt, parent_hiiro, git: git).build
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
