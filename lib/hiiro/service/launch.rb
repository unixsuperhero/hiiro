require 'fileutils'
require 'time'

class Hiiro
  class ServiceManager
    # Orchestrates launching a single service in tmux.
    # Handles script generation, env preparation, and state recording.
    class Launch
      include TmuxIntegration

      attr_reader :manager, :service, :tmux_info, :task_info,
                  :variation_overrides, :skip_env, :skip_window_creation

      def initialize(manager, service, tmux_info: {}, task_info: {},
                     variation_overrides: {}, skip_env: false, skip_window_creation: false)
        @manager = manager
        @service = service
        @tmux_info = tmux_info
        @task_info = task_info
        @variation_overrides = variation_overrides
        @skip_env = skip_env
        @skip_window_creation = skip_window_creation
      end

      # Execute the launch process.
      #
      # @return [Boolean] true if launched successfully
      def call
        script = launcher_script_path
        base_dir = manager.base_dir_path(service.base_dir)
        session = tmux_info[:session] || manager.current_tmux_session

        pane_id, window_target = pane_for_launch(session, base_dir)

        if pane_id
          manager.send_to_pane(pane_id, base_dir, script)
        else
          system("cd #{base_dir} && #{script} &")
        end

        record_state(session, window_target, pane_id)
        puts "Started service '#{service.name}'"
        true
      end

      private

      def pane_for_launch(session, base_dir)
        if session && !skip_window_creation
          window_target, pane_id = manager.create_tmux_window(session, service.name)
        elsif session && skip_window_creation
          pane_id = tmux_info[:pane]
          window_target = tmux_info[:window]
        else
          pane_id = nil
          window_target = nil
        end
        [pane_id, window_target]
      end

      def launcher_script_path
        dir = manager.scripts_dir
        init_cmds = Array(service.init || [])
        start_cmds = Array(service.start_cmd)

        init_path = shell_script_path(File.join(dir, "#{service.name}-init.sh"), init_cmds)
        start_path = shell_script_path(File.join(dir, "#{service.name}-start.sh"), start_cmds)
        env_path = skip_env ? nil : env_prep_script_path

        launcher_path = File.join(dir, "#{service.name}.sh")
        steps = []
        steps << "trap 'h service reset #{service.name}' EXIT"
        steps << init_path unless init_cmds.empty?
        steps << env_path if env_path
        steps << start_path

        shell_script_path(launcher_path, steps)
      end

      def shell_script_path(path, cmds)
        lines = ["#!/bin/bash"]
        lines.concat(cmds)
        File.write(path, lines.join("\n") + "\n")
        File.chmod(0755, path)
        path
      end

      def env_prep_script_path
        path = File.join(manager.scripts_dir, "#{service.name}-env.rb")
        overrides_literal = variation_overrides.map { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ")

        code = <<~RUBY
          #!/usr/bin/env ruby
          require 'hiiro'
          sm = Hiiro::ServiceManager.new
          sm.prepare_env(#{service.name.inspect}, variation_overrides: { #{overrides_literal} })
        RUBY

        File.write(path, code)
        File.chmod(0755, path)
        path
      end

      def record_state(session, window_target, pane_id)
        manager.record_running(service.name, {
          'pid' => nil,
          'tmux_session' => session || tmux_info[:session],
          'tmux_window' => window_target || tmux_info[:window],
          'tmux_pane' => pane_id,
          'task' => task_info[:task_name],
          'tree' => task_info[:tree],
          'branch' => task_info[:branch],
          'started_at' => Time.now.iso8601,
        })
      end

    end
  end
end
