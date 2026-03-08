require 'yaml'
require 'fileutils'
require_relative 'yaml_config'

class Hiiro
  class AppFiles
    include YamlConfig
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'app_files.yml')

    attr_reader :config_file

    def initialize(config_file: CONFIG_FILE)
      @config_file = config_file
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

    def self.build_hiiro(parent_hiiro, af, environment: nil)
      parent_hiiro.make_child(:file) do |h|
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

          # Resolve files relative to tree root if environment available
          resolved = files
          if environment
            tree = environment.tree
            if tree
              resolved = files.map { |f| File.join(tree.path, f) }
            end
          end

          editor = ENV['EDITOR'] || 'nvim'
          if editor.match?(/vim/i)
            system(editor, '-O', *resolved)
          else
            system(editor, *resolved)
          end
        end
      end
    end

    private
  end
end
