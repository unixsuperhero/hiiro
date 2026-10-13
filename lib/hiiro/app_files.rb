require 'yaml'
require 'fileutils'

class Hiiro
  class AppFiles
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'app_files.yml')

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

    def paths_for(app_name)
      context.validate!
      files_for(app_name).map do |file|
        path = File.expand_path(file, context.root_directory)
        ancestor = path
        ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor)
        unless File.exist?(ancestor) && context.contains?(ancestor) && context.contains?(path)
          raise Hiiro::Error, "Tracked file escapes root #{context.root_directory}: #{file}"
        end
        path
      end
    end

    def files_for(app_name)
      data = load_config
      data[app_name] || []
    end

    def add(app_name, *filenames)
      data = load_config
      data[app_name] ||= []
      filenames.flatten.each do |f|
        data[app_name] << f unless data[app_name].include?(f)
      end
      save_config(data)
      puts "Added #{filenames.length} file(s) to '#{app_name}'"
    end

    def remove(app_name, *filenames)
      data = load_config
      unless data.key?(app_name)
        puts "App '#{app_name}' not found in app files"
        return
      end

      filenames.flatten.each do |f|
        data[app_name].delete(f)
      end

      data.delete(app_name) if data[app_name].empty?
      save_config(data)
      puts "Removed #{filenames.length} file(s) from '#{app_name}'"
    end

    def list(app_name: nil)
      data = load_config

      if app_name
        files = data[app_name]
        if files && files.any?
          puts "Files for '#{app_name}':"
          files.each { |f| puts "  #{f}" }
        else
          puts "No files tracked for '#{app_name}'"
        end
      else
        if data.empty?
          puts "No app files configured."
          puts "Use 'file add <app> <file>' to track files."
          return
        end

        data.each do |name, files|
          puts "#{name}:"
          files.each { |f| puts "  #{f}" }
          puts
        end
      end
    end

    def self.build_hiiro(parent_hiiro, af, context: parent_hiiro.context, args: parent_hiiro.args)
      af.context = context
      parent_hiiro.make_child(:file, args, context: -> { af.context }) do |h|
        h.add_subcmd(:ls) do |app_name=nil|
          af.list(app_name: app_name)
        end

        h.add_subcmd(:add) do |app_name=nil, *filenames|
          unless app_name
            puts "Usage: file add <app_name> <file1> [file2 ...]"
            next
          end

          if filenames.empty?
            puts "Usage: file add <app_name> <file1> [file2 ...]"
            next
          end

          af.add(app_name, *filenames)
        end

        h.add_subcmd(:rm) do |app_name=nil, *filenames|
          unless app_name
            puts "Usage: file rm <app_name> <file1> [file2 ...]"
            next
          end

          if filenames.empty?
            puts "Usage: file rm <app_name> <file1> [file2 ...]"
            next
          end

          af.remove(app_name, *filenames)
        end

        h.add_subcmd(:edit) do |app_name=nil|
          unless app_name
            puts "Usage: file edit <app_name>"
            next
          end

          files = af.files_for(app_name)
          if files.empty?
            puts "No files tracked for '#{app_name}'"
            next
          end

          h.edit_files(*af.paths_for(app_name))
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
  end
end
