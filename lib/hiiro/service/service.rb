class Hiiro
  class ServiceManager
    # Value object for a service definition.
    # Encapsulates service configuration including start/stop commands,
    # env file management, and port/host settings.
    class Service
      attr_reader :name, :base_dir, :host, :port, :start_cmd, :stop_cmd,
                  :cleanup, :init, :env_files, :env_file, :base_env, :env_vars

      def initialize(name:, base_dir: nil, host: nil, port: nil, start: nil, stop: nil,
                     cleanup: nil, init: nil, env_files: nil, env_file: nil,
                     base_env: nil, env_vars: nil, **)
        @name = name
        @base_dir = base_dir
        @host = host || 'localhost'
        @port = port
        @start_cmd = start
        @stop_cmd = stop
        @cleanup = cleanup
        @init = init
        @env_files = env_files
        @env_file = env_file
        @base_env = base_env
        @env_vars = env_vars
      end

      # --- Computed Properties ---

      def url
        return nil unless port
        "http://#{host}:#{port}"
      end

      # Get env file configurations as a normalized array.
      #
      # @return [Array<Hash>] array of env file config hashes
      def env_file_configs
        if env_files
          Array(env_files).map { |ef| symbolize_keys(ef.is_a?(Hash) ? ef : {}) }
        elsif env_file || base_env || env_vars
          [{ env_file: env_file, base_env: base_env, env_vars: env_vars }]
        else
          []
        end
      end

      # --- Actor Methods ---

      # Launch this service.
      #
      # @param manager [ServiceManager] the service manager
      # @param tmux_info [Hash] tmux session/window info
      # @param task_info [Hash] current task context
      # @param variation_overrides [Hash] env var variation overrides
      # @param skip_env [Boolean] skip env file preparation
      # @param skip_window_creation [Boolean] use existing tmux pane
      # @return [Boolean] true if launched successfully
      def launch(manager:, tmux_info: {}, task_info: {}, variation_overrides: {},
                 skip_env: false, skip_window_creation: false)
        Launch.new(manager, self,
          tmux_info: tmux_info,
          task_info: task_info,
          variation_overrides: variation_overrides,
          skip_env: skip_env,
          skip_window_creation: skip_window_creation
        ).call
      end

      # Stop this service.
      #
      # @param manager [ServiceManager] the service manager
      # @return [Boolean] true if stopped successfully
      def stop(manager:)
        Stop.new(manager, self).call
      end

      private

      def symbolize_keys(hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end
