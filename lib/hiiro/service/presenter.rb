class Hiiro
  class ServiceManager
    # Presentation layer for service output formatting.
    module Presenter
      module_function

      # Print detailed status for a service.
      #
      # @param svc [Service] the service
      # @param info [Hash, nil] running state info
      # @param manager [ServiceManager] the manager
      def print_status(svc, info, manager)
        puts "Service: #{svc.name}"
        puts "Base dir: #{svc.base_dir || '(none)'}"
        puts "URL: #{svc.url || '(none)'}"

        if info
          puts "Status: running"
          puts "PID: #{info['pid'] || '(unknown)'}"
          puts "Pane: #{info['tmux_pane'] || '(unknown)'}"
          puts "Task: #{info['task'] || '(none)'}"
          puts "Started: #{info['started_at']}"
        else
          puts "Status: stopped"
        end
      end

      # Format a service line for list output.
      #
      # @param name [String] service name
      # @param cfg [Hash] service config
      # @param is_running [Boolean] whether service is running
      # @param info [Hash, nil] running state info
      # @param task_manager [TaskManager, nil] optional task manager for branch lookup
      # @return [String] formatted line
      def format_list_line(name, cfg, is_running, info, task_manager)
        status_emoji = is_running ? "\u{1F7E2}" : "\u{1F534}"
        host = cfg['host'] || 'localhost'
        url_str = cfg['port'] ? " #{host}:#{cfg['port']}" : ""
        extra = ""

        if is_running && info
          task = task_manager&.task_by_service_info(info)
          branch = task&.branch
          parts = [info['task'], branch].compact.reject(&:empty?)
          extra = "  (#{parts.join(' \u2022 ')})" unless parts.empty?
        end

        format("  %-20s  %s%s%s", name, status_emoji, url_str, extra)
      end

      # Format env file configuration info for a service.
      #
      # @param svc [Service] the service
      # @param manager [ServiceManager] the manager
      # @return [String] formatted env info
      def format_env_info(svc, manager)
        configs = svc.env_file_configs
        return "No env files configured for '#{svc.name}'" if configs.empty?

        lines = ["Env files for '#{svc.name}':"]
        configs.each do |efc|
          lines << ""
          lines << "  #{efc[:env_file] || '(no dest)'}"
          lines << "    template: #{efc[:base_env]}" if efc[:base_env]

          env_vars = efc[:env_vars]
          next unless env_vars

          env_vars.each do |var_name, var_config|
            variations = var_config.is_a?(Hash) && (var_config['variations'] || var_config[:variations])
            next unless variations

            lines << "    #{var_name}:"
            variations.each { |variation, value| lines << "      #{variation}: #{value}" }
          end
        end
        lines.join("\n")
      end
    end
  end
end
