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

    def self.add_resolvers(hiiro)
      sm = new
      hiiro.add_resolver(:service, -> { hiiro.fuzzyfind(sm.services.keys) }) do |name|
        sm.find_service(name)&.[](:name)
      end
    end

    def initialize(config_file: CONFIG_FILE, state_file: STATE_FILE)
      @config_file = config_file
      @state_file = state_file
    end

    def services
      load_config
    end

    def find_service(name)
      configs = services
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      match = result.resolved || result.first
      return nil unless match

      svc_name = match.item.name
      { name: svc_name, **symbolize_keys(configs[svc_name]) }
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
      { name: group_name, **symbolize_keys(configs[group_name]) }
    end

    def prepare_env(svc_name, variation_overrides: {})
      svc = find_service(svc_name)
      return unless svc

      base_dir = resolve_base_dir(svc[:base_dir])

      env_file_configs = build_env_file_configs(svc)
      return if env_file_configs.empty?

      env_file_configs.each do |efc|
        prepare_single_env(base_dir, efc, variation_overrides)
      end
    end

    def start_group(name, tmux_info: {}, task_info: {})
      group = find_group(name)
      unless group
        puts "Group '#{name}' not found"
        return false
      end

      members = group[:services]
      unless members && !members.empty?
        puts "Group '#{group[:name]}' has no services"
        return false
      end

      session = tmux_info[:session] || current_tmux_session
      unless session
        puts "tmux is required to start a service group"
        return false
      end

      puts "Starting group '#{group[:name]}'..."

      # Create one window for the group, split panes for each service
      window_target, first_pane_id = create_tmux_window(session, group[:name])
      last_pane_id = first_pane_id

      members.each_with_index do |member, idx|
        member_name = member['name'] || member[:name]
        use_overrides = member['use'] || member[:use] || {}

        svc = find_service(member_name)
        next unless svc

        if idx == 0
          pane_id = first_pane_id
        else
          # Split from the last pane so each new pane is distinct
          pane_id = split_tmux_pane(window_target, last_pane_id)
          last_pane_id = pane_id
        end

        member_tmux_info = tmux_info.merge(
          session: session,
          window: window_target,
          pane: pane_id,
        )

        start(member_name, tmux_info: member_tmux_info, task_info: task_info, variation_overrides: use_overrides, skip_window_creation: true)
      end
      true
    end

    def stop_group(name)
      group = find_group(name)
      unless group
        puts "Group '#{name}' not found"
        return false
      end

      members = group[:services]
      unless members && !members.empty?
        puts "Group '#{group[:name]}' has no services"
        return false
      end

      puts "Stopping group '#{group[:name]}'..."

      members.each do |member|
        member_name = member['name'] || member[:name]
        stop(member_name)
      end
      true
    end

    def reset_group(name)
      group = find_group(name)
      unless group
        puts "Group '#{name}' not found"
        return false
      end

      members = group[:services]
      unless members && !members.empty?
        puts "Group '#{group[:name]}' has no services"
        return false
      end

      puts "Resetting group '#{group[:name]}'..."

      members.each do |member|
        member_name = member['name'] || member[:name]
        reset(member_name)
      end
      true
    end

    def running?(name)
      state = load_state
      state.key?(name)
    end

    def running_services
      load_state
    end

    def reset(name)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return false
      end

      svc_name = svc[:name]
      state = load_state
      unless state.key?(svc_name)
        puts "Service '#{svc_name}' is not in running state"
        return false
      end

      state.delete(svc_name)
      save_state(state)
      puts "Reset service '#{svc_name}' (cleared from running state)"
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

    def start(name, tmux_info: {}, task_info: {}, variation_overrides: {}, skip_env: false, skip_window_creation: false)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return false
      end

      svc_name = svc[:name]

      if running?(svc_name)
        info = running_services[svc_name]
        puts "Service '#{svc_name}' is already running (pid: #{info['pid']}, pane: #{info['tmux_pane']})"
        return false
      end

      start_cmd = svc[:start]
      unless start_cmd
        puts "No start command configured for '#{svc_name}'"
        return false
      end

      # Build separate init/env/start scripts + a launcher that runs them in order
      init_cmds = Array(svc[:init] || [])
      start_cmds = Array(start_cmd)
      script = write_launcher_script(
        svc_name,
        init_cmds: init_cmds,
        start_cmds: start_cmds,
        env_prep: !skip_env,
        variation_overrides: variation_overrides,
      )

      base_dir = resolve_base_dir(svc[:base_dir])
      session = tmux_info[:session] || current_tmux_session

      if session && !skip_window_creation
        # Create a new tmux window for this service
        window_target, pane_id = create_tmux_window(session, svc_name)
      elsif session && skip_window_creation
        # Pane already created by start_group
        pane_id = tmux_info[:pane]
        window_target = tmux_info[:window]
      else
        pane_id = nil
        window_target = nil
      end

      if pane_id
        send_to_pane(pane_id, base_dir, script)
      else
        system("cd #{base_dir} && #{script} &")
      end

      # Record state
      state = load_state
      state[svc_name] = {
        'pid' => nil,
        'tmux_session' => session || tmux_info[:session],
        'tmux_window' => window_target || tmux_info[:window],
        'tmux_pane' => pane_id,
        'task' => task_info[:task_name],
        'tree' => task_info[:tree],
        'branch' => task_info[:branch],
        'started_at' => Time.now.iso8601,
      }
      save_state(state)

      puts "Started service '#{svc_name}'"
      true
    end

    def stop(name)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return false
      end

      svc_name = svc[:name]

      unless running?(svc_name)
        puts "Service '#{svc_name}' is not running"
        return false
      end

      info = running_services[svc_name]
      pane_id = info['tmux_pane']

      if svc[:stop] && !svc[:stop].to_s.strip.empty?
        stop_cmd = svc[:stop]
        if info['pid']
          stop_cmd = stop_cmd.gsub('$PID', info['pid'].to_s)
        end
        system(stop_cmd)
      elsif pane_id
        system('tmux', 'send-keys', '-t', pane_id, 'C-c')
      end

      # Run cleanup commands
      if svc[:cleanup]
        svc[:cleanup].each { |cmd| system(cmd) }
      end

      # Remove from state
      state = load_state
      state.delete(svc_name)
      save_state(state)

      puts "Stopped service '#{svc_name}'"
      true
    end

    def attach(name)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return false
      end

      svc_name = svc[:name]
      unless running?(svc_name)
        puts "Service '#{svc_name}' is not running"
        return false
      end

      info = running_services[svc_name]
      pane_id = info['tmux_pane']
      session = info['tmux_session']
      window = info['tmux_window']

      if session
        system('tmux', 'switch-client', '-t', session)
      end

      if window
        system('tmux', 'select-window', '-t', window)
      end

      if pane_id
        system('tmux', 'select-pane', '-t', pane_id)
      end

      true
    end

    def url(name)
      svc = find_service(name)
      return nil unless svc

      host = svc[:host] || 'localhost'
      port = svc[:port]
      return nil unless port

      "http://#{host}:#{port}"
    end

    def port(name)
      svc = find_service(name)
      svc&.[](:port)
    end

    def host(name)
      svc = find_service(name)
      svc&.[](:host) || 'localhost'
    end

    def status(name)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return
      end

      svc_name = svc[:name]
      puts "Service: #{svc_name}"
      puts "Base dir: #{svc[:base_dir] || '(none)'}"
      puts "URL: #{url(svc_name) || '(none)'}"

      if running?(svc_name)
        info = running_services[svc_name]
        puts "Status: running"
        puts "PID: #{info['pid'] || '(unknown)'}"
        puts "Pane: #{info['tmux_pane'] || '(unknown)'}"
        puts "Task: #{info['task'] || '(none)'}"
        puts "Started: #{info['started_at']}"
      else
        puts "Status: stopped"
      end
    end

    def services_for_dir(base_dir)
      configs = services
      configs.select { |_, v| v['base_dir'] == base_dir }
    end

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

    def self.build_hiiro(parent_hiiro, sm, task_manager: nil)
      parent_hiiro.make_child(:service) do |h|
        h.add_subcmd(:ls) do
          configs = sm.services
          if configs.empty?
            puts "No services configured."
            puts "Use 'service add' to add one, or edit #{sm.config_file}"
            next
          end

          running = sm.running_services
          puts "Services:"
          puts
          configs
            .sort_by{ |name,_| running.key?(name) ? :running : :stopped }
            .each do |name, cfg|
              is_running = running.key?(name)
              status_emoji = is_running ? "🟢" : "🔴"
              host = cfg['host'] || 'localhost'
              url_str = cfg['port'] ? " #{host}:#{cfg['port']}" : ""
              extra = ""
              if is_running
                info = running[name]
                task = task_manager&.task_by_service_info(info)
                branch = task&.branch
                parts = [info['task'], branch].compact.reject(&:empty?)
                extra = "  (#{parts.join(' • ')})" unless parts.empty?
              end
              puts format("  %-20s  %s%s%s", name, status_emoji, url_str, extra)
          end
        end

        h.add_subcmd(:list) do
          h.run_subcmd(:ls)
        end

        h.add_subcmd(:start) do |svc_name=nil, *extra_args|
          unless svc_name
            all = sm.services.keys
            if all.empty?
              puts "No services configured"
              next
            end
            svc_name = h.fuzzyfind(all)
            next unless svc_name
          end

          # Parse --use flags from extra_args
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

          tmux_info = {
            session: h.tmux_client.current_session&.name,
          }

          task_info = {}
          if task_manager
            task = task_manager.current_task
            if task
              task_info = {
                task_name: task.name,
                tree: task.tree_name,
                branch: task.branch,
                session: task.session_name,
              }
            end
          end

          # Check if it's a group or individual service
          group = sm.find_group(svc_name)
          if group
            sm.start_group(svc_name, tmux_info: tmux_info, task_info: task_info)
          else
            sm.start(svc_name, tmux_info: tmux_info, task_info: task_info, variation_overrides: variation_overrides)
          end
        end

        h.add_subcmd(:stop) do |svc_name=nil|
          unless svc_name
            running = sm.running_services.keys
            if running.empty?
              puts "No running services"
              next
            end
            svc_name = h.fuzzyfind(running)
            next unless svc_name
          end

          # Check if it's a group or individual service
          group = sm.find_group(svc_name)
          if group
            sm.stop_group(svc_name)
          else
            sm.stop(svc_name)
          end
        end

        h.add_subcmd(:reset) do |svc_name=nil|
          unless svc_name
            running = sm.running_services.keys
            if running.empty?
              puts "No running services"
              next
            end
            svc_name = h.fuzzyfind(running)
            next unless svc_name
          end

          # Check if it's a group or individual service
          group = sm.find_group(svc_name)
          if group
            sm.reset_group(svc_name)
          else
            sm.reset(svc_name)
          end
        end

        h.add_subcmd(:clean) do
          sm.clean
        end

        h.add_subcmd(:attach) do |svc_name=nil|
          unless svc_name
            running = sm.running_services.keys
            if running.empty?
              puts "No running services"
              next
            end
            svc_name = h.fuzzyfind(running)
            next unless svc_name
          end

          sm.attach(svc_name)
        end

        h.add_subcmd(:open) do |svc_name=nil|
          unless svc_name
            puts "Usage: service open <name>"
            next
          end

          svc_url = sm.url(svc_name)
          if svc_url
            system('open', svc_url)
          else
            puts "No URL configured for '#{svc_name}'"
          end
        end

        h.add_subcmd(:url) do |svc_name=nil|
          unless svc_name
            puts "Usage: service url <name>"
            next
          end

          svc_url = sm.url(svc_name)
          if svc_url
            puts svc_url
          else
            puts "No URL configured for '#{svc_name}'"
          end
        end

        h.add_subcmd(:port) do |svc_name=nil|
          unless svc_name
            puts "Usage: service port <name>"
            next
          end

          p = sm.port(svc_name)
          if p
            puts p
          else
            puts "No port configured for '#{svc_name}'"
          end
        end

        h.add_subcmd(:status) do |svc_name=nil|
          unless svc_name
            running = sm.running_services.keys
            if running.empty?
              puts "No running services"
              next
            end
            svc_name = h.fuzzyfind(running)
            next unless svc_name
          end

          sm.status(svc_name)
        end

        h.add_subcmd(:add) do |*add_args|
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

          input = InputFile.yaml_file(hiiro: h, content: YAML.dump({ 'new_service' => template }), prefix: 'service')
          input.edit

          begin
            data = input.parsed_file(permitted_classes: [Symbol]) || {}
            data.each do |name, cfg|
              sm.add_service({ 'name' => name }.merge(cfg || {}))
            end
          rescue => e
            puts "Error parsing config: #{e.message}"
          ensure
            input.cleanup
          end
        end

        h.add_subcmd(:rm) do |svc_name=nil|
          unless svc_name
            puts "Usage: service rm <name>"
            next
          end

          sm.remove_service(svc_name)
        end

        h.add_subcmd(:remove) do |svc_name=nil|
          unless svc_name
            puts "Usage: service remove <name>"
            next
          end

          sm.remove_service(svc_name)
        end

        h.add_subcmd(:config) do
          h.edit_files(sm.config_file)
        end

        h.add_subcmd(:groups) do
          configs = sm.services
          groups = configs.select { |_, v| v.is_a?(Hash) && v.key?('services') }

          if groups.empty?
            puts "No service groups configured."
            next
          end

          puts "Service groups:"
          puts
          groups.each do |name, cfg|
            members = (cfg['services'] || []).map { |m| m['name'] || m[:name] }.compact
            puts format("  %-20s  %s", name, members.join(', '))
          end
        end

        h.add_subcmd(:env) do |svc_name=nil|
          unless svc_name
            puts "Usage: service env <name>"
            next
          end

          svc = sm.find_service(svc_name)
          unless svc
            puts "Service '#{svc_name}' not found"
            next
          end

          configs = sm.send(:build_env_file_configs, svc)
          if configs.empty?
            puts "No env files configured for '#{svc[:name]}'"
            next
          end

          puts "Env files for '#{svc[:name]}':"
          configs.each do |efc|
            puts
            puts "  #{efc[:env_file] || '(no dest)'}"
            puts "    template: #{efc[:base_env]}" if efc[:base_env]

            env_vars = efc[:env_vars]
            next unless env_vars

            env_vars.each do |var_name, var_config|
              variations = var_config.is_a?(Hash) && (var_config['variations'] || var_config[:variations])
              next unless variations

              puts "    #{var_name}:"
              variations.each do |variation, value|
                puts "      #{variation}: #{value}"
              end
            end
          end
        end
      end
    end

    private

    # Normalize env file config into an array of hashes,
    # supporting both old single-env format and new env_files array
    def build_env_file_configs(svc)
      if svc[:env_files]
        Array(svc[:env_files]).map { |ef| symbolize_keys(ef.is_a?(Hash) ? ef : {}) }
      elsif svc[:env_file] || svc[:base_env] || svc[:env_vars]
        [{ env_file: svc[:env_file], base_env: svc[:base_env], env_vars: svc[:env_vars] }]
      else
        []
      end
    end

    def prepare_single_env(base_dir, efc, variation_overrides)
      env_file = efc[:env_file]
      base_env = efc[:base_env]
      env_vars = efc[:env_vars]

      # Copy base env template if configured
      if base_env && env_file
        src = File.join(ENV_TEMPLATES_DIR, base_env)
        dest = File.join(base_dir, env_file)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end
      end

      # Inject variation values into env file
      return unless env_vars && env_file

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

    def stale_pane?(pane_id)
      return true unless pane_id
      !system('tmux', 'has-session', '-t', pane_id, [:out, :err] => '/dev/null')
    end

    def scripts_dir
      dir = File.join(STATE_DIR, 'scripts')
      FileUtils.mkdir_p(dir)
      dir
    end

    def write_shell_script(path, cmds)
      lines = ["#!/bin/bash"]
      lines.concat(cmds)
      File.write(path, lines.join("\n") + "\n")
      File.chmod(0755, path)
      path
    end

    def write_env_prep_script(svc_name, variation_overrides)
      path = File.join(scripts_dir, "#{svc_name}-env.rb")
      overrides_literal = variation_overrides.map { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ")

      code = <<~RUBY
        #!/usr/bin/env ruby
        require 'hiiro'
        sm = Hiiro::ServiceManager.new
        sm.prepare_env(#{svc_name.inspect}, variation_overrides: { #{overrides_literal} })
      RUBY

      File.write(path, code)
      File.chmod(0755, path)
      path
    end

    def write_launcher_script(svc_name, init_cmds:, start_cmds:, env_prep: true, variation_overrides: {})
      dir = scripts_dir

      # Write init script (may be empty)
      init_path = File.join(dir, "#{svc_name}-init.sh")
      write_shell_script(init_path, init_cmds)

      # Write start script
      start_path = File.join(dir, "#{svc_name}-start.sh")
      write_shell_script(start_path, start_cmds)

      # Write env prep script
      env_path = nil
      if env_prep
        env_path = write_env_prep_script(svc_name, variation_overrides)
      end

      # Write launcher that orchestrates: init -> env -> start -> reset
      # Use trap to ensure reset runs even on Ctrl+C
      launcher_path = File.join(dir, "#{svc_name}.sh")
      steps = []
      steps << "trap 'h service reset #{svc_name}' EXIT"
      steps << init_path unless init_cmds.empty?
      steps << env_path if env_path
      steps << start_path

      write_shell_script(launcher_path, steps)
    end

    def current_tmux_session
      Hiiro::Tmux::Session.current&.name
    end

    def create_tmux_window(session, name)
      pane_id = `tmux new-window -d -t #{session} -n #{name} -P -F '\#{pane_id}'`.chomp
      window_target = "#{session}:#{name}"
      [window_target, pane_id]
    end

    def split_tmux_pane(window_target, target_pane_id)
      pane_id = `tmux split-window -d -t #{target_pane_id} -P -F '\#{pane_id}'`.chomp
      system('tmux', 'select-layout', '-t', window_target, 'even-vertical')
      pane_id
    end

    def send_to_pane(pane_id, base_dir, script)
      system('tmux', 'send-keys', '-t', pane_id, "cd #{base_dir} && #{script}", 'Enter')
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
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    def resolve_base_dir(base_dir)
      return Dir.pwd if base_dir.nil? || base_dir.to_s.empty?

      git_root = `git rev-parse --show-toplevel 2>/dev/null`.chomp
      root = git_root.empty? ? Dir.pwd : git_root

      File.join(root, base_dir)
    end
  end
end
