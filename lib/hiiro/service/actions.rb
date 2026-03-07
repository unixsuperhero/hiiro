require 'yaml'
require 'tempfile'

class Hiiro
  class ServiceManager
    # High-level actions with side effects for service operations.
    # Each method implements a user-facing command.
    module Actions
      module_function

      def list(sm, tm)
        configs = sm.services
        if configs.empty?
          puts "No services configured."
          puts "Use 'service add' to add one, or edit #{sm.config_file}"
          return
        end

        running = sm.running_services
        puts "Services:"
        puts

        configs
          .sort_by { |name, _| running.key?(name) ? :running : :stopped }
          .each do |name, cfg|
            is_running = running.key?(name)
            info = running[name]
            puts Presenter.format_list_line(name, cfg, is_running, info, tm)
          end
      end

      def start(sm, h, svc_name, extra_args, tm)
        unless svc_name
          all = sm.services.keys
          if all.empty?
            puts "No services configured"
            return
          end
          svc_name = h.fuzzyfind(all)
          return unless svc_name
        end

        variation_overrides = parse_use_flags(extra_args)
        tmux_info = { session: ENV['TMUX'] ? `tmux display-message -p '#S'`.chomp : nil }
        task_info = build_task_info(tm)

        group = sm.find_group(svc_name)
        if group
          sm.start_group(svc_name, tmux_info: tmux_info, task_info: task_info)
        else
          sm.start(svc_name, tmux_info: tmux_info, task_info: task_info, variation_overrides: variation_overrides)
        end
      end

      def stop(sm, h, svc_name)
        unless svc_name
          running = sm.running_services.keys
          if running.empty?
            puts "No running services"
            return
          end
          svc_name = h.fuzzyfind(running)
          return unless svc_name
        end

        group = sm.find_group(svc_name)
        group ? sm.stop_group(svc_name) : sm.stop(svc_name)
      end

      def reset(sm, h, svc_name)
        unless svc_name
          running = sm.running_services.keys
          if running.empty?
            puts "No running services"
            return
          end
          svc_name = h.fuzzyfind(running)
          return unless svc_name
        end

        group = sm.find_group(svc_name)
        group ? sm.reset_group(svc_name) : sm.reset(svc_name)
      end

      def attach(sm, h, svc_name)
        unless svc_name
          running = sm.running_services.keys
          if running.empty?
            puts "No running services"
            return
          end
          svc_name = h.fuzzyfind(running)
          return unless svc_name
        end
        sm.attach(svc_name)
      end

      def open(sm, svc_name)
        unless svc_name
          puts "Usage: service open <name>"
          return
        end

        svc_url = sm.url(svc_name)
        if svc_url
          system('open', svc_url)
        else
          puts "No URL configured for '#{svc_name}'"
        end
      end

      def url(sm, svc_name)
        unless svc_name
          puts "Usage: service url <name>"
          return
        end

        svc_url = sm.url(svc_name)
        puts svc_url || "No URL configured for '#{svc_name}'"
      end

      def port(sm, svc_name)
        unless svc_name
          puts "Usage: service port <name>"
          return
        end

        p = sm.port(svc_name)
        puts p || "No port configured for '#{svc_name}'"
      end

      def status(sm, h, svc_name)
        unless svc_name
          running = sm.running_services.keys
          if running.empty?
            puts "No running services"
            return
          end
          svc_name = h.fuzzyfind(running)
          return unless svc_name
        end
        sm.status(svc_name)
      end

      def add(sm)
        template = {
          'base_dir' => '',
          'host' => 'localhost',
          'port' => '',
          'init' => [],
          'start' => [''],
          'cleanup' => [],
          'env_files' => [
            { 'env_file' => '.env', 'base_env' => '', 'env_vars' => {} },
          ],
        }

        tmpfile = Tempfile.new(['service', '.yml'])
        tmpfile.write(YAML.dump({ 'new_service' => template }))
        tmpfile.close

        editor = ENV['EDITOR'] || 'nvim'
        system(editor, tmpfile.path)

        begin
          data = YAML.safe_load_file(tmpfile.path, permitted_classes: [Symbol]) || {}
          data.each do |name, cfg|
            sm.add_service({ 'name' => name }.merge(cfg || {}))
          end
        rescue => e
          puts "Error parsing config: #{e.message}"
        ensure
          tmpfile.unlink
        end
      end

      def remove(sm, svc_name)
        unless svc_name
          puts "Usage: service rm <name>"
          return
        end
        sm.remove_service(svc_name)
      end

      def config(sm)
        editor = ENV['EDITOR'] || 'nvim'
        system(editor, sm.config_file)
      end

      def groups(sm)
        configs = sm.services
        groups = configs.select { |_, v| v.is_a?(Hash) && v.key?('services') }

        if groups.empty?
          puts "No service groups configured."
          return
        end

        puts "Service groups:"
        puts
        groups.each do |name, cfg|
          members = (cfg['services'] || []).map { |m| m['name'] || m[:name] }.compact
          puts format("  %-20s  %s", name, members.join(', '))
        end
      end

      def env(sm, svc_name)
        unless svc_name
          puts "Usage: service env <name>"
          return
        end

        svc = sm.find_service(svc_name)
        unless svc
          puts "Service '#{svc_name}' not found"
          return
        end

        puts Presenter.format_env_info(svc, sm)
      end

      # --- Helpers ---

      def parse_use_flags(extra_args)
        variation_overrides = {}
        extra_args.each_with_index do |arg, i|
          if arg == '--use' && extra_args[i + 1]
            key, val = extra_args[i + 1].split('=', 2)
            variation_overrides[key] = val if key && val
          elsif arg.start_with?('--use=')
            key, val = arg.sub('--use=', '').split('=', 2)
            variation_overrides[key] = val if key && val
          end
        end
        variation_overrides
      end

      def build_task_info(tm)
        return {} unless tm

        task = tm.current_task
        return {} unless task

        {
          task_name: task.name,
          tree: task.tree_name,
          branch: task.branch,
          session: task.session_name,
        }
      end
    end
  end
end
