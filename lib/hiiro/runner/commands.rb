require 'tempfile'
require 'yaml'

class Hiiro
  class RunnerTool
    # Command builder for RunnerTool, following the BaseCommands pattern.
    class Commands < Hiiro::BaseCommands
      def initialize(manager, parent_hiiro, git: nil)
        super(manager, parent_hiiro, git: git)
      end

      protected

      def command_prefix
        :run
      end

      def register_commands(h)
        rt = manager
        git = get_context(:git)

        h.add_default do |*run_args|
          parsed = parse_run_args(run_args)
          rt.run(**parsed, git: git)
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

          tmpfile = Tempfile.new(['tool', '.yml'])
          tmpfile.write(YAML.dump({ 'new_tool' => template }))
          tmpfile.close

          editor = ENV['EDITOR'] || 'nvim'
          system(editor, tmpfile.path)

          begin
            data = YAML.safe_load_file(tmpfile.path, permitted_classes: [Symbol]) || {}
            data.each do |name, cfg|
              rt.add_tool({ 'name' => name }.merge(cfg || {}))
            end
          rescue => e
            puts "Error parsing config: #{e.message}"
          ensure
            tmpfile.unlink
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
          rt.edit_config
        end
      end

      private

      def parse_run_args(run_args)
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
          if RunnerTool::KNOWN_CHANGE_SETS.include?(arg)
            change_set = arg
          elsif RunnerTool::KNOWN_TOOL_TYPES.include?(arg)
            tool_type = arg
          else
            file_type_group ||= arg
          end
        end

        {
          change_set: change_set || 'dirty',
          tool_type: tool_type,
          file_type_group: file_type_group,
          variation: variation
        }
      end
    end
  end
end
