require 'yaml'
require 'fileutils'
require 'time'
require 'ostruct'

class Hiiro
  class ServiceManager
    # Core service manager responsible for service lifecycle and state.
    # Handles service lookup, start/stop operations, and configuration.
    class Manager
      include YamlConfigurable
      include TmuxIntegration
      include Matchable

      # Define constants locally - they're also in ServiceManager for backwards compat
      DEFAULT_CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'services.yml')
      DEFAULT_STATE_DIR = File.join(Dir.home, '.config', 'hiiro', 'services')
      DEFAULT_STATE_FILE = File.join(DEFAULT_STATE_DIR, 'running.yml')

      attr_reader :config_file, :state_file

      def initialize(config_file: DEFAULT_CONFIG_FILE, state_file: DEFAULT_STATE_FILE)
        @config_file = config_file
        @state_file = state_file
      end

      # --- Data Access ---

      def services
        load_config
      end

      def running_services
        load_state
      end

      def running?(name)
        running_services.key?(name)
      end

      # --- Service/Group Lookup ---

      def find_service(name)
        configs = services
        names = configs.keys.map { |k| OpenStruct.new(name: k) }
        match = find_by_prefix(names, name, key: :name)
        return nil unless match

        svc_name = match.name
        Service.new(name: svc_name, **symbolize_keys(configs[svc_name]))
      end

      def find_group(name)
        configs = services
        names = configs.keys.select { |k| configs[k].is_a?(Hash) && configs[k].key?('services') }
        return nil if names.empty?

        structs = names.map { |k| OpenStruct.new(name: k) }
        match = find_by_prefix(structs, name, key: :name)
        return nil unless match

        group_name = match.name
        Group.new(name: group_name, **symbolize_keys(configs[group_name]))
      end

      def url(name)
        svc = find_service(name)
        svc&.url
      end

      def port(name)
        svc = find_service(name)
        svc&.port
      end

      def host(name)
        svc = find_service(name)
        svc&.host || 'localhost'
      end

      # --- High-Level Actions ---

      def start(name, tmux_info: {}, task_info: {}, variation_overrides: {},
                skip_env: false, skip_window_creation: false)
        svc = find_service(name)
        unless svc
          puts "Service '#{name}' not found"
          return false
        end

        if running?(svc.name)
          info = running_services[svc.name]
          puts "Service '#{svc.name}' is already running (pid: #{info['pid']}, pane: #{info['tmux_pane']})"
          return false
        end

        unless svc.start_cmd
          puts "No start command configured for '#{svc.name}'"
          return false
        end

        svc.launch(
          manager: self,
          tmux_info: tmux_info,
          task_info: task_info,
          variation_overrides: variation_overrides,
          skip_env: skip_env,
          skip_window_creation: skip_window_creation
        )
      end

      def stop(name)
        svc = find_service(name)
        unless svc
          puts "Service '#{name}' not found"
          return false
        end

        unless running?(svc.name)
          puts "Service '#{svc.name}' is not running"
          return false
        end

        svc.stop(manager: self)
      end

      def reset(name)
        svc = find_service(name)
        unless svc
          puts "Service '#{name}' not found"
          return false
        end

        unless running?(svc.name)
          puts "Service '#{svc.name}' is not in running state"
          return false
        end

        state = load_state
        state.delete(svc.name)
        save_state(state)
        puts "Reset service '#{svc.name}' (cleared from running state)"
        true
      end

      def attach(name)
        svc = find_service(name)
        unless svc
          puts "Service '#{name}' not found"
          return false
        end

        unless running?(svc.name)
          puts "Service '#{svc.name}' is not running"
          return false
        end

        info = running_services[svc.name]
        switch_to_tmux_target(
          session: info['tmux_session'],
          window: info['tmux_window'],
          pane: info['tmux_pane']
        )
        true
      end

      def clean
        state = load_state
        return puts("No running services to clean") if state.empty?

        stale = state.select { |_, info| !pane_exists?(info['tmux_pane']) }
        if stale.empty?
          puts "All running services have live panes"
          return false
        end

        stale.each do |svc_name, _|
          state.delete(svc_name)
          puts "Cleaned stale service '#{svc_name}'"
        end
        save_state(state)
        true
      end

      def status(name)
        svc = find_service(name)
        unless svc
          puts "Service '#{name}' not found"
          return
        end

        Presenter.print_status(svc, running_services[svc.name], self)
      end

      # --- Group Operations ---

      def start_group(name, tmux_info: {}, task_info: {})
        group = find_group(name)
        unless group
          puts "Group '#{name}' not found"
          return false
        end

        unless group.members.any?
          puts "Group '#{group.name}' has no services"
          return false
        end

        group.launch(manager: self, tmux_info: tmux_info, task_info: task_info)
      end

      def stop_group(name)
        group = find_group(name)
        unless group
          puts "Group '#{name}' not found"
          return false
        end

        puts "Stopping group '#{group.name}'..."
        group.stop(manager: self)
      end

      def reset_group(name)
        group = find_group(name)
        unless group
          puts "Group '#{name}' not found"
          return false
        end

        puts "Resetting group '#{group.name}'..."
        group.members.each { |m| reset(m.name) }
        true
      end

      # --- Env Preparation ---

      def prepare_env(svc_name, variation_overrides: {})
        svc = find_service(svc_name)
        return unless svc

        EnvPreparation.new(svc, variation_overrides: variation_overrides).call
      end

      # --- Config Management ---

      def add_service(config_hash)
        name = config_hash.delete('name') || config_hash.delete(:name)
        unless name
          puts "Service name required"
          return false
        end

        configs = load_config
        if configs.key?(name)
          puts "Service '#{name}' already exists"
          return false
        end

        configs[name] = config_hash.transform_keys(&:to_s)
        save_config(configs)
        puts "Added service '#{name}'"
        true
      end

      def remove_service(name)
        configs = load_config
        unless configs.key?(name)
          puts "Service '#{name}' not found"
          return false
        end

        configs.delete(name)
        save_config(configs)
        puts "Removed service '#{name}'"
        true
      end

      # --- State Management ---

      def record_running(svc_name, info)
        state = load_state
        state[svc_name] = info
        save_state(state)
      end

      def clear_running(svc_name)
        state = load_state
        state.delete(svc_name)
        save_state(state)
      end

      # --- Script/Path Helpers (noun-named per Phase 5) ---

      def scripts_dir
        dir = File.join(STATE_DIR, 'scripts')
        FileUtils.mkdir_p(dir)
        dir
      end

      def current_tmux_session
        current_session_name
      end

      def base_dir_path(base_dir)
        return Dir.pwd if base_dir.nil? || base_dir.to_s.empty?

        git_root = `git rev-parse --show-toplevel 2>/dev/null`.chomp
        root = git_root.empty? ? Dir.pwd : git_root

        File.join(root, base_dir)
      end

      # Backwards compatibility alias
      alias_method :resolve_base_dir, :base_dir_path

      private

      def load_config
        load_yaml(config_file, default: {})
      end

      def save_config(data)
        save_yaml(config_file, data)
      end

      def load_state
        load_yaml(state_file, default: {})
      end

      def save_state(data)
        save_yaml(state_file, data)
      end
    end
  end
end
