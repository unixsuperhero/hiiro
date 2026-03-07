require 'yaml'
require 'fileutils'
require 'time'
require 'ostruct'

class Hiiro
  class ServiceManager
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'services.yml')
    STATE_DIR = File.join(Dir.home, '.config', 'hiiro', 'services')
    STATE_FILE = File.join(STATE_DIR, 'running.yml')
    ENV_TEMPLATES_DIR = File.join(Dir.home, '.config', 'hiiro', 'env_templates')

    attr_reader :config_file, :state_file

    def initialize(config_file: CONFIG_FILE, state_file: STATE_FILE)
      @config_file = config_file
      @state_file = state_file
    end

    # --- Data Access (Low-Level) ---

    def services
      load_config
    end

    def running_services
      load_state
    end

    def running?(name)
      running_services.key?(name)
    end

    # --- Service/Group Lookup (Low-Level) ---

    def find_service(name)
      configs = services
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      match = result.resolved || result.first
      return nil unless match

      svc_name = match.item.name
      Service.new(name: svc_name, **symbolize_keys(configs[svc_name]))
    end

    def find_group(name)
      configs = services
      names = configs.keys.select { |k| configs[k].is_a?(Hash) && configs[k].key?('services') }
      return nil if names.empty?

      structs = names.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(structs, :name).by_prefix(name)
      match = result.resolved || result.first
      return nil unless match

      group_name = match.item.name
      ServiceGroup.new(name: group_name, **symbolize_keys(configs[group_name]))
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

    def start(name, tmux_info: {}, task_info: {}, variation_overrides: {}, skip_env: false, skip_window_creation: false)
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

      launcher = ServiceLauncher.new(self, svc,
        tmux_info: tmux_info,
        task_info: task_info,
        variation_overrides: variation_overrides,
        skip_env: skip_env,
        skip_window_creation: skip_window_creation
      )
      launcher.launch
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

      stopper = ServiceStopper.new(self, svc)
      stopper.stop
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
      system('tmux', 'switch-client', '-t', info['tmux_session']) if info['tmux_session']
      system('tmux', 'select-window', '-t', info['tmux_window']) if info['tmux_window']
      system('tmux', 'select-pane', '-t', info['tmux_pane']) if info['tmux_pane']
      true
    end

    def clean
      state = load_state
      return puts("No running services to clean") if state.empty?

      stale = state.select { |_, info| stale_pane?(info['tmux_pane']) }
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

      ServicePresenter.print_status(svc, running_services[svc.name], self)
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

      GroupLauncher.new(self, group, tmux_info: tmux_info, task_info: task_info).launch
    end

    def stop_group(name)
      group = find_group(name)
      unless group
        puts "Group '#{name}' not found"
        return false
      end

      puts "Stopping group '#{group.name}'..."
      group.members.each { |m| stop(m.name) }
      true
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

      EnvPreparer.new(svc, variation_overrides: variation_overrides).prepare
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

    # --- Script/Tmux Helpers ---

    def scripts_dir
      dir = File.join(STATE_DIR, 'scripts')
      FileUtils.mkdir_p(dir)
      dir
    end

    def current_tmux_session
      return nil unless ENV['TMUX']
      `tmux display-message -p '#S'`.chomp
    end

    def create_tmux_window(session, name)
      pane_id = `tmux new-window -d -t #{session} -n #{name} -P -F '\\#{pane_id}'`.chomp
      window_target = "#{session}:#{name}"
      [window_target, pane_id]
    end

    def split_tmux_pane(window_target, target_pane_id)
      pane_id = `tmux split-window -d -t #{target_pane_id} -P -F '\\#{pane_id}'`.chomp
      system('tmux', 'select-layout', '-t', window_target, 'even-vertical')
      pane_id
    end

    def send_to_pane(pane_id, base_dir, script)
      system('tmux', 'send-keys', '-t', pane_id, "cd #{base_dir} && #{script}", 'Enter')
    end

    def resolve_base_dir(base_dir)
      return Dir.pwd if base_dir.nil? || base_dir.to_s.empty?

      git_root = `git rev-parse --show-toplevel 2>/dev/null`.chomp
      root = git_root.empty? ? Dir.pwd : git_root

      File.join(root, base_dir)
    end

    # --- Hiiro Integration ---

    def self.build_hiiro(parent_hiiro, sm, task_manager: nil)
      ServiceCommands.new(sm, parent_hiiro, task_manager: task_manager).build
    end

    private

    def stale_pane?(pane_id)
      return true unless pane_id
      !system('tmux', 'has-session', '-t', pane_id, [:out, :err] => '/dev/null')
    end

    def load_config
      return {} unless File.exist?(config_file)
      YAML.safe_load_file(config_file, permitted_classes: [Symbol]) || {}
    end

    def save_config(data)
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, YAML.dump(data))
    end

    def load_state
      return {} unless File.exist?(state_file)
      YAML.safe_load_file(state_file, permitted_classes: [Symbol]) || {}
    end

    def save_state(data)
      FileUtils.mkdir_p(File.dirname(state_file))
      File.write(state_file, YAML.dump(data))
    end

    def symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end

  # Value object for a service definition
  class Service
    attr_reader :name, :base_dir, :host, :port, :start_cmd, :stop_cmd, :cleanup, :init, :env_files, :env_file, :base_env, :env_vars

    def initialize(name:, base_dir: nil, host: nil, port: nil, start: nil, stop: nil, cleanup: nil, init: nil, env_files: nil, env_file: nil, base_env: nil, env_vars: nil, **_)
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

    def url
      return nil unless port
      "http://#{host}:#{port}"
    end

    def env_file_configs
      if env_files
        Array(env_files).map { |ef| symbolize_keys(ef.is_a?(Hash) ? ef : {}) }
      elsif env_file || base_env || env_vars
        [{ env_file: env_file, base_env: base_env, env_vars: env_vars }]
      else
        []
      end
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end

  # Value object for a service group
  class ServiceGroup
    attr_reader :name, :services_config

    def initialize(name:, services: [], **_)
      @name = name
      @services_config = services || []
    end

    def members
      @members ||= services_config.map do |m|
        member_name = m['name'] || m[:name]
        use_overrides = m['use'] || m[:use] || {}
        GroupMember.new(name: member_name, use_overrides: use_overrides)
      end
    end
  end

  # Value object for a group member
  class GroupMember
    attr_reader :name, :use_overrides

    def initialize(name:, use_overrides: {})
      @name = name
      @use_overrides = use_overrides
    end
  end

  # Orchestrates launching a single service
  class ServiceLauncher
    attr_reader :manager, :service, :tmux_info, :task_info, :variation_overrides, :skip_env, :skip_window_creation

    def initialize(manager, service, tmux_info: {}, task_info: {}, variation_overrides: {}, skip_env: false, skip_window_creation: false)
      @manager = manager
      @service = service
      @tmux_info = tmux_info
      @task_info = task_info
      @variation_overrides = variation_overrides
      @skip_env = skip_env
      @skip_window_creation = skip_window_creation
    end

    def launch
      script = write_launcher_script
      base_dir = manager.resolve_base_dir(service.base_dir)
      session = tmux_info[:session] || manager.current_tmux_session

      pane_id, window_target = create_or_use_pane(session, base_dir)

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

    def create_or_use_pane(session, base_dir)
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

    def write_launcher_script
      dir = manager.scripts_dir
      init_cmds = Array(service.init || [])
      start_cmds = Array(service.start_cmd)

      init_path = write_shell_script(File.join(dir, "#{service.name}-init.sh"), init_cmds)
      start_path = write_shell_script(File.join(dir, "#{service.name}-start.sh"), start_cmds)
      env_path = skip_env ? nil : write_env_prep_script

      launcher_path = File.join(dir, "#{service.name}.sh")
      steps = []
      steps << "trap 'h service reset #{service.name}' EXIT"
      steps << init_path unless init_cmds.empty?
      steps << env_path if env_path
      steps << start_path

      write_shell_script(launcher_path, steps)
    end

    def write_shell_script(path, cmds)
      lines = ["#!/bin/bash"]
      lines.concat(cmds)
      File.write(path, lines.join("\n") + "\n")
      File.chmod(0755, path)
      path
    end

    def write_env_prep_script
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

  # Handles stopping a service
  class ServiceStopper
    attr_reader :manager, :service

    def initialize(manager, service)
      @manager = manager
      @service = service
    end

    def stop
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
  end

  # Orchestrates launching a service group
  class GroupLauncher
    attr_reader :manager, :group, :tmux_info, :task_info

    def initialize(manager, group, tmux_info: {}, task_info: {})
      @manager = manager
      @group = group
      @tmux_info = tmux_info
      @task_info = task_info
    end

    def launch
      session = tmux_info[:session] || manager.current_tmux_session
      unless session
        puts "tmux is required to start a service group"
        return false
      end

      puts "Starting group '#{group.name}'..."

      window_target, first_pane_id = manager.create_tmux_window(session, group.name)
      last_pane_id = first_pane_id

      group.members.each_with_index do |member, idx|
        svc = manager.find_service(member.name)
        next unless svc

        if idx == 0
          pane_id = first_pane_id
        else
          pane_id = manager.split_tmux_pane(window_target, last_pane_id)
          last_pane_id = pane_id
        end

        member_tmux_info = tmux_info.merge(
          session: session,
          window: window_target,
          pane: pane_id,
        )

        manager.start(member.name,
          tmux_info: member_tmux_info,
          task_info: task_info,
          variation_overrides: member.use_overrides,
          skip_window_creation: true
        )
      end
      true
    end
  end

  # Handles env file preparation
  class EnvPreparer
    ENV_TEMPLATES_DIR = ServiceManager::ENV_TEMPLATES_DIR

    attr_reader :service, :variation_overrides

    def initialize(service, variation_overrides: {})
      @service = service
      @variation_overrides = variation_overrides
    end

    def prepare
      base_dir = resolve_base_dir
      service.env_file_configs.each do |efc|
        prepare_single_env(base_dir, efc)
      end
    end

    private

    def resolve_base_dir
      base = service.base_dir
      return Dir.pwd if base.nil? || base.to_s.empty?

      git_root = `git rev-parse --show-toplevel 2>/dev/null`.chomp
      root = git_root.empty? ? Dir.pwd : git_root
      File.join(root, base)
    end

    def prepare_single_env(base_dir, efc)
      env_file = efc[:env_file]
      base_env = efc[:base_env]
      env_vars = efc[:env_vars]

      copy_base_template(base_dir, base_env, env_file) if base_env && env_file
      inject_variations(base_dir, env_file, env_vars) if env_vars && env_file
    end

    def copy_base_template(base_dir, base_env, env_file)
      src = File.join(ENV_TEMPLATES_DIR, base_env)
      dest = File.join(base_dir, env_file)
      if File.exist?(src)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    def inject_variations(base_dir, env_file, env_vars)
      dest = File.join(base_dir, env_file)
      lines = File.exist?(dest) ? File.readlines(dest) : []

      env_vars.each do |var_name, var_config|
        var_config = symbolize_keys(var_config) if var_config.is_a?(Hash)
        variations = var_config.is_a?(Hash) && (var_config[:variations] || var_config['variations'])
        next unless variations

        variation = (variation_overrides[var_name] || variation_overrides[var_name.to_sym] || 'local').to_s
        value = variations[variation]
        next unless value

        replaced = false
        lines.map! do |line|
          if line.match?(/\A#{Regexp.escape(var_name.to_s)}=/)
            replaced = true
            "#{var_name}=#{value}\n"
          else
            line
          end
        end
        lines << "#{var_name}=#{value}\n" unless replaced
      end

      File.write(dest, lines.join)
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end

  # Presentation layer for service output
  module ServicePresenter
    module_function

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

  # Handles building the Hiiro command interface
  class ServiceCommands
    attr_reader :manager, :parent_hiiro, :task_manager

    def initialize(manager, parent_hiiro, task_manager: nil)
      @manager = manager
      @parent_hiiro = parent_hiiro
      @task_manager = task_manager
    end

    def build
      sm = manager
      tm = task_manager

      parent_hiiro.make_child(:service) do |h|
        h.add_subcmd(:ls) { ServiceActions.list(sm, tm) }
        h.add_subcmd(:list) { ServiceActions.list(sm, tm) }
        h.add_subcmd(:start) { |svc_name=nil, *extra| ServiceActions.start(sm, h, svc_name, extra, tm) }
        h.add_subcmd(:stop) { |svc_name=nil| ServiceActions.stop(sm, h, svc_name) }
        h.add_subcmd(:reset) { |svc_name=nil| ServiceActions.reset(sm, h, svc_name) }
        h.add_subcmd(:clean) { sm.clean }
        h.add_subcmd(:attach) { |svc_name=nil| ServiceActions.attach(sm, h, svc_name) }
        h.add_subcmd(:open) { |svc_name=nil| ServiceActions.open(sm, svc_name) }
        h.add_subcmd(:url) { |svc_name=nil| ServiceActions.url(sm, svc_name) }
        h.add_subcmd(:port) { |svc_name=nil| ServiceActions.port(sm, svc_name) }
        h.add_subcmd(:status) { |svc_name=nil| ServiceActions.status(sm, h, svc_name) }
        h.add_subcmd(:add) { ServiceActions.add(sm) }
        h.add_subcmd(:rm) { |svc_name=nil| ServiceActions.remove(sm, svc_name) }
        h.add_subcmd(:remove) { |svc_name=nil| ServiceActions.remove(sm, svc_name) }
        h.add_subcmd(:config) { ServiceActions.config(sm) }
        h.add_subcmd(:groups) { ServiceActions.groups(sm) }
        h.add_subcmd(:env) { |svc_name=nil| ServiceActions.env(sm, svc_name) }
      end
    end
  end

  # High-level actions with side effects
  module ServiceActions
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
          puts ServicePresenter.format_list_line(name, cfg, is_running, info, tm)
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

      require 'tempfile'
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

      puts ServicePresenter.format_env_info(svc, sm)
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
