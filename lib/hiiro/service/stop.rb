class Hiiro
  class ServiceManager
    # Handles stopping a running service.
    # Sends stop command or Ctrl-C, runs cleanup, and updates state.
    class Stop
      attr_reader :manager, :service

      def initialize(manager, service)
        @manager = manager
        @service = service
      end

      # Execute the stop process.
      #
      # @return [Boolean] true if stopped successfully
      def call
        info = manager.running_services[service.name]
        pane_id = info['tmux_pane']

        if service.stop_cmd && !service.stop_cmd.to_s.strip.empty?
          stop_cmd = service.stop_cmd
          stop_cmd = stop_cmd.gsub('$PID', info['pid'].to_s) if info['pid']
          system(stop_cmd)
        elsif pane_id
          system('tmux', 'send-keys', '-t', pane_id, 'C-c')
        end

        if service.cleanup
          service.cleanup.each { |cmd| system(cmd) }
        end

        manager.clear_running(service.name)
        puts "Stopped service '#{service.name}'"
        true
      end

      # Alias for backwards compatibility
      alias_method :execute, :call
    end
  end
end
