require 'yaml'
require 'fileutils'
require 'time'
require 'ostruct'
require 'shellwords'
require 'digest'
require 'json'

class Hiiro
  class ServiceManager
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'services.yml')
    STATE_DIR = File.join(Dir.home, '.config', 'hiiro', 'services')
    STATE_FILE = File.join(STATE_DIR, 'running.yml')
    ENV_TEMPLATES_DIR = File.join(Dir.home, '.config', 'hiiro', 'env_templates')

    attr_reader :config_file, :state_file
    attr_writer :herdr, :context, :launcher

    # One running copy of a definition: the same definition in another
    # directory, task, or variation is a different instance with its own run.
    Instance = Struct.new(:key, :record, keyword_init: true) do
      def definition = record['definition'] || key
      def directory  = record['directory']
      def task       = record['task']
      def run_id     = record['run_id']
      def owned?     = !run_id.nil?
    end

    def self.instance_key(definition, directory, task, variations)
      identity = JSON.generate([directory, task, (variations || {}).to_h.transform_keys(&:to_s).sort])
      "#{definition}@#{Digest::SHA1.hexdigest(identity)[0, 8]}"
    end

    def self.add_resolvers(hiiro)
      sm = new
      hiiro.add_resolver(:service, -> { hiiro.fuzzyfind(sm.services.keys) }) do |name|
        sm.find_service(name)&.[](:name)
      end
    end

    def initialize(config_file: CONFIG_FILE, state_file: STATE_FILE, herdr: Hiiro::Herdr.client, context: nil)
      @config_file = config_file
      @state_file = state_file
      @herdr = herdr
      @context = context
    end

    # A callable context (the root `h` mounts pass one) resolves on first use, so help needs no task.
    def context
      @context = @context.call if @context.respond_to?(:call)
      @context ||= CurrentTask.new(pin: false).context
    end

    def services
      load_config
    end

    def find_service(name)
      raise Hiiro::Error, 'Service name is required' if name.to_s.strip.empty?
      configs = services
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      raise Hiiro::Error, "Ambiguous service '#{name}'" if !result.resolved && result.matches.size > 1
      match = result.resolved
      return nil unless match

      svc_name = match.item.name
      { name: svc_name, **symbolize_keys(configs[svc_name]) }
    end

    def find_group(name)
      service = find_service(name)
      service if service && service.key?(:services)
    end

    # The matched service as a ServiceDefinition (prefix match like find_service).
    def definition_for(name)
      svc = find_service(name)
      return nil unless svc

      ServiceDefinition.from_config(svc[:name], services[svc[:name]], root: context.root_directory, cwd: context.start_directory)
    end

    def group_definition_for(name)
      group = find_group(name)
      group && ServiceGroup.from_config(group[:name], services[group[:name]])
    end

    def prepare_env(svc_name, variation_overrides: {})
      definition = definition_for(svc_name)
      return unless definition
      validate_directory!(definition.base_directory)

      definition.environment_files.each do |env_file|
        prepare_single_env(env_file, variation_overrides)
      end
    end

    def start_group(name, herdr_info: {}, task_info: {})
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

      calling_workspace = context_workspace
      workspace = resolve_herdr_workspace(herdr_info[:workspace] || calling_workspace)
      unless workspace
        puts "Herdr is required to start a service group"
        return false
      end

      members.each do |member|
        member_name = member['name'] || member[:name]
        definition = definition_for(member_name)
        raise Hiiro::Error, "Service '#{member_name}' not found" unless definition
        validate_directory!(definition.base_directory)
      end

      puts "Starting group '#{group[:name]}'..."

      members.each do |member|
        member_name = member['name'] || member[:name]
        use_overrides = member['use'] || member[:use] || {}

        svc = find_service(member_name)
        next unless svc

        start(
          member_name,
          herdr_info: herdr_info.merge(workspace: workspace),
          task_info: task_info,
          variation_overrides: use_overrides
        )
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

    def instances
      load_state.map { |key, record| Instance.new(key: key, record: record || {}) }
    end

    def instances_of(definition_name)
      instances.select { |instance| instance.definition == definition_name }
    end

    def run_for(instance)
      instance.owned? ? launcher.store.find(instance.run_id) : nil
    end

    def active?(instance)
      !!run_for(instance)&.active?
    end

    # An exact instance key, or a definition whose single instance (or single
    # instance in the current task/directory) is meant.
    def resolve_instance(name)
      state = load_state
      return Instance.new(key: name, record: state[name] || {}) if state.key?(name)

      svc = find_service(name)
      return nil unless svc

      candidates = instances_of(svc[:name])
      return candidates.first if candidates.size <= 1

      directory = File.realpath(definition_for(svc[:name]).base_directory) rescue nil
      here = candidates.select { |instance| instance.directory == directory && instance.task == context.task&.name }
      return here.first if here.one?

      raise Hiiro::Error, "Several '#{svc[:name]}' instances; choose one: #{candidates.map(&:key).join(', ')}"
    end

    def reset(name)
      instance = resolve_instance(name)
      unless instance
        puts "Service '#{name}' is not in running state"
        return false
      end

      state = load_state
      state.delete(instance.key)
      save_state(state)
      puts "Reset service '#{instance.key}' (cleared from running state)"
      true
    end

    def clean
      state = load_state
      return puts("No running services to clean") if state.empty?

      stale = instances.select do |instance|
        instance.owned? ? !active?(instance) : stale_pane?(instance.record['herdr_pane'])
      end
      if stale.empty?
        puts "All recorded services are still running"
        return false
      end

      stale.each do |instance|
        state.delete(instance.key)
        puts "Cleaned service '#{instance.key}' (#{run_for(instance)&.summary || 'no live pane'})"
      end
      save_state(state)
      true
    end

    def start(name, herdr_info: {}, task_info: {}, variation_overrides: {}, skip_env: false)
      svc = find_service(name)
      unless svc
        puts "Service '#{name}' not found"
        return false
      end

      svc_name = svc[:name]
      start_cmd = svc[:start]
      unless start_cmd
        puts "No start command configured for '#{svc_name}'"
        return false
      end

      definition = definition_for(svc_name)
      base_dir = validate_directory!(definition.base_directory)
      key = self.class.instance_key(svc_name, base_dir, task_info[:task_name], variation_overrides)
      existing = Instance.new(key: key, record: load_state[key] || {})
      if active?(existing)
        puts "Service '#{svc_name}' is already running as #{key} (#{run_for(existing).summary})"
        return false
      end

      calling_workspace = context_workspace
      workspace = resolve_herdr_workspace(herdr_info[:workspace] || calling_workspace)

      script = write_launcher_script(
        key,
        svc_name,
        init_cmds: Array(svc[:init] || []),
        start_cmds: Array(start_cmd),
        env_prep: !skip_env,
        variation_overrides: variation_overrides,
      )
      ready = definition.ready_command && CommandSpecification.shell(definition.ready_command, cwd: base_dir)
      request = OwnedRun::LaunchRequest.new(
        owner: { kind: 'service', definition: svc_name, instance: key, directory: base_dir, task: task_info[:task_name] },
        command: CommandSpecification.new('/bin/bash', script, cwd: base_dir),
        placement: { 'kind' => workspace ? 'herdr-tab' : 'detached' },
        process_group: true,
        ready: ready,
      )
      record = {
        'definition' => svc_name,
        'directory' => base_dir,
        'task' => task_info[:task_name],
        'tree' => task_info[:tree],
        'branch' => task_info[:branch],
        'variations' => variation_overrides.to_h,
        'run_id' => request.id,
        'herdr_workspace' => workspace&.id,
        'workspace_name' => workspace&.name,
        'started_at' => Time.now.iso8601,
      }
      save_record = lambda do |run|
        record.merge!(run.terminal.to_meta) if run.terminal
        state = load_state
        state[key] = record
        save_state(state)
      end

      run = if workspace
        launcher.herdr_tab(request, workspace: workspace, name: svc_name, on_allocated: save_record)
      else
        launcher.detached(request, on_allocated: save_record)
      end

      puts "Started service '#{svc_name}' as #{key} (#{run.summary})"
      true
    rescue OwnedRun::LaunchError => e
      puts "Service '#{svc_name}' did not start: #{e.run.error}"
      false
    end

    # Stops one identified instance: signals only the recorded process when its
    # identity still matches, waits for it to exit, then cleans up and forgets it.
    def stop(name)
      instance = resolve_instance(name)
      unless instance
        puts "Service '#{name}' is not running"
        return false
      end

      unless instance.owned?
        puts "Service '#{instance.key}' has no owned run to stop; stop it yourself, then run `h service reset #{instance.key}`"
        return false
      end

      definition = definition_for(instance.definition)
      raise Hiiro::Error, "Service '#{instance.definition}' is no longer configured" unless definition
      base_dir = validate_directory!(instance.directory || definition.base_directory)
      run = run_for(instance)

      if run&.allocated?
        run = launcher.store.update(run.id) { |record| record.fail('stopped before start') if record.allocated? }
      end

      if run&.active?
        process = run.process
        if process.alive?
          return false unless signal_stop(definition, run, base_dir)

          unless wait_for_exit(run, process, definition.stop_timeout)
            puts "Service '#{instance.key}' (pid #{process.pid}) did not exit within #{definition.stop_timeout}s; state retained"
            return false
          end
        else
          puts "Process #{process.pid} for '#{instance.key}' is gone or was reused; not signalling it"
        end
        run = launcher.store.update(run.id) { |record| record.fail('exited without a recorded status') if record.active? }
      end

      cleanup_ok = definition.cleanup_commands.map { |cmd| system(cmd, chdir: base_dir) }.all?
      puts "Cleanup for '#{instance.key}' failed" unless cleanup_ok

      state = load_state
      state.delete(instance.key)
      save_state(state)

      puts "Stopped service '#{instance.key}' (#{run&.summary || 'no run record'})"
      cleanup_ok
    end

    def attach(name)
      instance = resolve_instance(name)
      unless instance
        puts "Service '#{name}' is not running"
        return false
      end

      workspace_id = instance.record['herdr_workspace']
      tab_id = instance.record['herdr_tab']

      herdr.focus_workspace(workspace_id) if workspace_id
      herdr.focus_tab(tab_id) if tab_id

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
      puts "Readiness: #{svc[:ready] ? svc[:ready] : '(not configured)'}"

      found = instances_of(svc_name)
      puts "Status: stopped" if found.empty?
      found.each do |instance|
        run = run_for(instance)
        puts
        puts "Instance: #{instance.key}"
        puts "Status: #{run ? run.summary : 'unowned (started by an older hiiro)'}"
        puts "Directory: #{instance.directory || '(unknown)'}"
        puts "Pane: #{instance.record['herdr_pane'] || '(none)'}"
        puts "Task: #{instance.task || '(none)'}"
        puts "Variations: #{instance.record['variations'].to_h.map { |k, v| "#{k}=#{v}" }.join(', ')}" unless instance.record['variations'].to_h.empty?
        puts "Started: #{instance.record['started_at']}"
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

    def self.build_hiiro(parent_hiiro, sm, context: parent_hiiro.context, args: parent_hiiro.args)
      sm.context = context
      parent_hiiro.make_child(:service, args, context: -> { sm.context }) do |h|
        h.add_subcmd(:ls) do
          configs = sm.services
          if configs.empty?
            puts "No services configured."
            puts "Use 'service add' to add one, or edit #{sm.config_file}"
            next
          end

          found = sm.instances.group_by(&:definition)
          puts "Services:"
          puts
          configs
            .sort_by { |name, _| found.key?(name) ? 0 : 1 }
            .each do |name, cfg|
              host = cfg['host'] || 'localhost'
              url_str = cfg['port'] ? " #{host}:#{cfg['port']}" : ""
              list = found.fetch(name, [])
              active = list.any? { |instance| sm.active?(instance) }
              puts format("  %-20s  %s%s", name, active ? "🟢" : "🔴", url_str)
              list.each do |instance|
                run = sm.run_for(instance)
                parts = [instance.task, instance.record['branch']].compact.reject(&:empty?)
                extra = parts.empty? ? '' : "  (#{parts.join(' • ')})"
                puts format("    %-24s  %s  %s%s", instance.key, run ? run.summary : 'unowned', instance.directory, extra)
              end
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

          sm.herdr = h.herdr_client
          task_info = {}
          if (task = sm.context.task)
            task_info = { task_name: task.name, tree: task.tree_name, branch: task.branch, session: task.session_name }
          end

          # Check if it's a group or individual service
          group = sm.find_group(svc_name)
          if group
            sm.start_group(svc_name, task_info: task_info)
          else
            sm.start(svc_name, task_info: task_info, variation_overrides: variation_overrides)
          end
        end

        h.add_subcmd(:stop) do |svc_name=nil|
          unless svc_name
            running = sm.instances.map(&:key)
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
            running = sm.instances.map(&:key)
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
            running = sm.instances.map(&:key)
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
            running = sm.instances.map(&:key)
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
            puts format("  %-20s  %s", name, ServiceGroup.from_config(name, cfg).service_names.join(', '))
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

          env_files = sm.definition_for(svc_name).environment_files
          if env_files.empty?
            puts "No env files configured for '#{svc[:name]}'"
            next
          end

          puts "Env files for '#{svc[:name]}':"
          env_files.each do |ef|
            puts
            puts "  #{ef.spec[:env_file] || '(no dest)'}"
            puts "    template: #{ef.spec[:base_env]}" if ef.spec[:base_env]

            ef.variables.each do |var_name, variations|
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

    def prepare_single_env(env_file, variation_overrides)
      dest = env_file.destination_path

      # Copy base env template if configured
      if env_file.template_path && dest && File.exist?(env_file.template_path)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(env_file.template_path, dest)
      end

      # Inject variation values into env file
      return unless dest && env_file.spec[:env_vars]

      existing = File.exist?(dest) ? File.readlines(dest) : []
      File.write(dest, env_file.desired_content(existing, variation_overrides).join)
    end

    def stale_pane?(pane_id)
      return true unless pane_id
      herdr.get_pane(pane_id).nil?
    end

    def scripts_dir
      dir = File.join(File.dirname(state_file), 'scripts')
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

    def instance_scripts_dir(key)
      dir = File.join(scripts_dir, key)
      FileUtils.mkdir_p(dir)
      dir
    end

    def write_env_prep_script(key, svc_name, variation_overrides)
      path = File.join(instance_scripts_dir(key), "env.rb")
      overrides_literal = variation_overrides.map { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ")

      code = <<~RUBY
        #!/usr/bin/env ruby
        require 'hiiro'
        context = Hiiro::TaskLocation.for(nil, root: #{context.root_directory.inspect}, invocation_directory: #{context.invocation_directory.inspect})
        context = context.with_directory(#{context.start_directory.inspect}, source: :override)
        sm = Hiiro::ServiceManager.new(config_file: #{File.expand_path(config_file).inspect}, state_file: #{File.expand_path(state_file).inspect}, context: context)
        sm.prepare_env(#{svc_name.inspect}, variation_overrides: { #{overrides_literal} })
      RUBY

      File.write(path, code)
      File.chmod(0755, path)
      path
    end

    # init -> env -> start, each failure ending the run with its exit status.
    # The start script replaces the launcher so the run's pid is the service.
    def write_launcher_script(key, svc_name, init_cmds:, start_cmds:, env_prep: true, variation_overrides: {})
      dir = instance_scripts_dir(key)
      start_path = write_shell_script(File.join(dir, "start.sh"), start_cmds)

      steps = ["set -e"]
      steps << "/bin/bash -e #{Shellwords.escape(write_shell_script(File.join(dir, 'init.sh'), init_cmds))}" unless init_cmds.empty?
      if env_prep
        env_path = write_env_prep_script(key, svc_name, variation_overrides)
        steps << Shellwords.join([RbConfig.ruby, '-I', File.expand_path('..', __dir__), env_path])
      end
      steps << "exec /bin/bash #{Shellwords.escape(start_path)}"

      write_shell_script(File.join(dir, "launch.sh"), steps)
    end

    def signal_stop(definition, run, base_dir)
      pid = run.process.pid
      if definition.stop_command && !definition.stop_command.to_s.strip.empty?
        return true if system(definition.stop_command.gsub('$PID', pid.to_s), chdir: base_dir)

        puts "Stop command for '#{run.owner['instance']}' failed; state retained"
        return false
      end

      Process.kill('TERM', run.process_group? ? -pid : pid)
      true
    rescue Errno::ESRCH
      true
    end

    # Exit is observed when the process is gone and its supervisor recorded an outcome.
    def wait_for_exit(run, process, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until !process.alive? && launcher.store.find(run.id).finished?
        return !process.alive? if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
      true
    end

    def launcher
      @launcher ||= OwnedRun::Launcher.new(herdr: herdr)
    end

    def context_workspace
      terminal = context.terminal.validate!(herdr)
      terminal.workspace_id && herdr.get_workspace(terminal.workspace_id)
    end

    def resolve_herdr_workspace(workspace)
      return workspace if workspace.respond_to?(:id)
      return nil unless workspace

      herdr.find_workspace(workspace)
    end

    def herdr
      @herdr ||= Hiiro::Herdr.client
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

    def validate_directory!(directory)
      raise Hiiro::Error, "Service directory does not exist: #{directory}" unless File.directory?(directory)
      File.realpath(directory)
    end
  end
end
