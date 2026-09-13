require 'fileutils'
require 'time'
require 'uri'

class Hiiro
  class TaskCLI
    class Error < StandardError; end

    HELP = <<~TEXT
      Usage: t COMMAND [ARGS] [-t TASK | --task TASK]

      list [--all]                 List active/waiting tasks; --all includes done/archive
      show [TASK]                  Show a task and its references
      current                      Print the task inferred from this directory/workspace
      new TASK                     Create a record and ~/notes/work/TASK, nothing else
      next [TEXT...] [--clear]      Read, set, or clear the next action
      status [STATE]               Read/set active, waiting, done, or archived
      waiting [TEXT...] [--clear]   Read/set what the task is waiting on
      done | archive               Change status; preserve every resource

      directory add PATH [--primary] [--label LABEL]
      directory list | open [ID|PATH|LABEL]
      link add URL [--kind general|issue|thread] [--label LABEL]
      link list [--kind KIND] | open [ID|URL|LABEL]
      pr add URL [--label LABEL] | list | open [ID|URL|LABEL]
      file add PATH [--label LABEL] | list | open [ID|PATH|LABEL]
      doc new NAME [TITLE...] | list | open [NAME]
      workspace open [--directory PATH] | show
      tab list | new [LABEL] [--directory PATH] [--command COMMAND] | open ID|LABEL
      pane list | open ID|LABEL | read ID|LABEL | run ID|LABEL COMMAND...
      pane split ID|LABEL [--direction right|down] [--directory PATH] [--command COMMAND]

      Options may appear before or after the command. Use -- before literal text
      beginning with a dash. Explicit task names are exact, never fuzzy matched.
      Without -t, directory and Herdr context must identify exactly one task.
      doc open uses mdoc; other open commands use the system default application.
      Run t help for this help. No command creates a Git worktree.
    TEXT

    def self.options
      Hiiro::Options.setup do
        option :task, short: :t, multi: true, desc: 'Exact task name'
        option :kind, desc: 'Link kind: general, issue, or thread'
        option :label, desc: 'Resource label'
        option :directory, desc: 'Existing directory for a workspace, tab, or pane'
        option :command, desc: 'Command to run in a new tab or pane'
        option :direction, default: 'right', desc: 'Pane split direction: right or down'
        flag :all, short: :a, desc: 'Include done and archived tasks'
        flag :clear, desc: 'Clear next action or waiting text'
        flag :primary, desc: 'Use this directory as the primary code directory'
      end
    end

    def self.run(argv = ARGV)
      definitions = options
      validate_options!(argv, definitions)
      parsed = definitions.parse(argv)
      raise Error, 'Conflicting --task selectors' if parsed.task.uniq.length > 1

      command_args = parsed.help? ? ['help'] : parsed.args
      Hiiro.run(args: command_args, external_commands: false) do |h|
        new(h, parsed).install(h)
      end
    rescue Error => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    def self.validate_options!(argv, definitions)
      remaining = argv.dup
      until remaining.empty?
        arg = remaining.shift
        break if arg == '--'
        next unless arg.start_with?('-') && arg != '-'

        name, inline = arg.split('=', 2)
        definition = definitions.definitions.values.find do |entry|
          name == entry.long_form || (entry.short && name == "-#{entry.short}")
        end
        raise Error, "Unknown option #{name}" unless definition
        if definition.flag?
          raise Error, "#{name} does not take a value" if inline
        else
          value = inline || remaining.shift
          raise Error, "#{name} requires a value" if value.nil? || value.empty? || value.start_with?('-')
        end
      end
    end

    def initialize(hiiro, options)
      @hiiro = hiiro
      @options = options
    end

    def install(h)
      command(h, :help) { puts HELP }
      command(h, :list, :ls) { |args| list(args) }
      command(h, :show) { |args| show(select_task(positional: single(args, optional: true))) }
      command(h, :current) { |args| no_args!(args); puts select_task.name }
      command(h, :new) { |args| create(single(args)) }
      command(h, :next) { |args| metadata(:next_action, args) }
      command(h, :waiting) { |args| metadata(:waiting_on, args) }
      command(h, :status) do |args|
        state = single(args, optional: true)
        task = select_task
        state ? set_status(task, state) : puts(task.task_status)
      end
      %w[done archive].each do |name|
        command(h, name) do |args|
          no_args!(args)
          set_status(select_task, name == 'archive' ? 'archived' : 'done')
        end
      end
      %w[directory link pr file doc workspace tab pane].each do |group|
        h.add_subcmd(group) do |*args|
          h.make_child(group, args, external_commands: false) { |child| install_group(child, group) }.run
        end
      end
      h.add_default do |*args|
        if args.empty?
          puts HELP
        else
          warn "Unknown command: #{args.join(' ')}. Run t help."
          false
        end
      end
    end

    private

    def command(h, *names, &action)
      h.add_subcmd(*names) do |*args|
        begin
          action.call(args)
          true
        rescue Error, ArgumentError, SystemCallError, Sequel::Error => e
          warn "ERROR: #{e.message}"
          false
        end
      end
    end

    def install_group(h, group)
      case group
      when 'directory', 'link', 'pr', 'file'
        command(h, :add) { |args| add_resource(group, single(args)) }
        command(h, :list, :ls) { |args| no_args!(args); list_resources(group, select_task) }
        command(h, :open) { |args| open_resource(group, single(args, optional: true)) }
      when 'doc'
        command(h, :new) { |args| new_doc(args) }
        command(h, :list, :ls) { |args| no_args!(args); documents(select_task).each { |path| puts path } }
        command(h, :open) { |args| open_doc(single(args, optional: true)) }
      when 'workspace'
        command(h, :open) { |args| no_args!(args); open_workspace }
        command(h, :show) { |args| no_args!(args); show_workspace }
      when 'tab'
        command(h, :list, :ls) { |args| no_args!(args); client.tabs(workspace: workspace_for(select_task)).each { |tab| puts tab } }
        command(h, :new) { |args| new_tab(single(args, optional: true)) }
        command(h, :open) do |args|
          workspace = workspace_for(select_task)
          tab = live_item(client.tabs(workspace: workspace), single(args))
          check_result(client.focus_workspace(workspace.id))
          check_result(client.focus_tab(tab.id))
        end
      when 'pane'
        command(h, :list, :ls) { |args| no_args!(args); client.panes(workspace: workspace_for(select_task)).each { |pane| puts pane } }
        %w[open read split run].each do |action|
          command(h, action) { |args| pane_action(action, args) }
        end
      end
      h.add_default do |*args|
        if args.empty?
          puts HELP.lines.grep(/^#{group} /).join
        else
          warn "Unknown #{group} command: #{args.join(' ')}. Run t help."
          false
        end
      end
    end

    def single(args, optional: false)
      raise Error, 'Too many arguments' if args.length > 1
      raise Error, 'An argument is required; run t help' if !optional && args.empty?
      args.first
    end

    def no_args!(args)
      raise Error, "Unexpected arguments: #{args.join(' ')}" unless args.empty?
    end

    def safe_name!(name)
      unless name && name.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/) && name.bytesize <= 120
        raise Error, 'Use a name of 1-120 ASCII letters, digits, dots, underscores, or hyphens, starting with a letter or digit'
      end
      name
    end

    def select_task(positional: nil)
      explicit = [*@options.task, positional].compact.uniq
      raise Error, 'Conflicting task names' if explicit.length > 1
      if explicit.one?
        return TaskRecord.find_by_name(explicit.first) || raise(Error, "Task not found: #{explicit.first}")
      end

      tasks = TaskRecord.all_as_list
      cwd = File.realpath(Dir.pwd)
      matches = tasks.select do |task|
        paths = [task.home, code_directory(task), *task.resources.where(kind: 'directory').select_map(:target)].compact
        paths.any? { |path| inside?(cwd, path) }
      end
      if ENV['HERDR_WORKSPACE_ID'] || ENV['HERDR_PANE_ID'] || ENV['HERDR_ENV'] == '1'
        herdr = client
        pane = herdr.get_pane(ENV['HERDR_PANE_ID']) if ENV['HERDR_PANE_ID']
        if ENV['HERDR_PANE_ID'] && !pane
          raise Error, 'Cannot resolve the current Herdr pane; specify --task'
        end
        workspace_id = ENV['HERDR_WORKSPACE_ID'] || pane&.workspace_id
        if pane && workspace_id != pane.workspace_id
          raise Error, 'Conflicting Herdr pane/workspace context; specify --task'
        end
        workspace = workspace_id ? herdr.get_workspace(workspace_id) : herdr.current_workspace
        raise Error, 'Cannot resolve the current Herdr workspace; specify --task' unless workspace
        matches.concat(tasks.select { |task| workspace_label(task) == workspace.name })
      end
      matches.uniq!(&:id)
      raise Error, 'No current task; specify --task TASK' if matches.empty?
      raise Error, "Ambiguous task context: #{matches.map(&:name).join(', ')}; specify --task" unless matches.one?
      matches.first
    end

    def inside?(path, directory)
      return false unless Dir.exist?(directory)
      root = File.realpath(directory)
      path == root || path.start_with?(root + File::SEPARATOR)
    end

    def ensure_home(task)
      root = File.dirname(task.home)
      FileUtils.mkdir_p(root)
      if File.symlink?(task.home) || (File.exist?(task.home) && !Dir.exist?(task.home))
        raise Error, "Task home must be a directory, not a symlink or file: #{task.home}"
      end
      FileUtils.mkdir_p(task.home)
      raise Error, 'Task home escapes the notes work directory' unless inside?(File.realpath(task.home), root)
      task.home
    end

    def create(name)
      safe_name!(name)
      unless @options.task.empty? || @options.task == [name]
        raise Error, 'new TASK conflicts with --task'
      end
      record = TaskRecord.find_by_name(name)
      if record
        ensure_home(record)
        puts "Task already exists: #{name}\n#{record.home}"
        return
      end
      now = Time.now.iso8601
      record = TaskRecord.new(name: name, session: name, status: 'active', created_at: now, updated_at: now)
      ensure_home(record)
      record.save
      puts "Created #{name}\n#{record.home}"
    end

    def list(args)
      no_args!(args)
      tasks = @options.task.empty? ? TaskRecord.all_as_list : [select_task]
      tasks.reject! { |task| %w[done archived].include?(task.task_status) } unless @options.all
      tasks.each { |task| puts [task.name, task.task_status, task.next_action, task.waiting_on].compact.join("\t") }
      puts 'No tasks. Create one with t new TASK.' if tasks.empty?
    end

    def show(task)
      puts "#{task.name} [#{task.task_status}]"
      puts "Home: #{task.home}"
      puts "Next: #{task.next_action}" if task.next_action
      puts "Waiting: #{task.waiting_on}" if task.waiting_on
      puts "Code: #{code_directory(task)}" if code_directory(task)
      puts "Workspace label: #{workspace_label(task)}"
      task.resources.each { |resource| print_resource(resource) }
      documents(task).each { |path| puts "Document: #{path}" }
    end

    def metadata(field, args)
      task = select_task
      raise Error, 'Use text or --clear, not both' if @options.clear && !args.empty?
      if args.empty? && !@options.clear
        puts task[field] if task[field]
        return
      end
      text = @options.clear ? nil : args.join(' ')
      changes = { field => text, updated_at: Time.now.iso8601 }
      if field == :waiting_on
        if text
          changes.merge!(status: 'waiting', completed_at: nil, archived_at: nil)
        elsif task.task_status == 'waiting'
          changes[:status] = 'active'
        end
      end
      task.update(changes)
      show(task)
    end

    def set_status(task, state)
      raise Error, "Status must be #{TaskRecord::STATUSES.join(', ')}" unless TaskRecord::STATUSES.include?(state)
      now = Time.now.iso8601
      changes = { status: state, updated_at: now }
      case state
      when 'done'
        changes.merge!(completed_at: task.completed_at || now, archived_at: nil)
      when 'archived'
        changes[:archived_at] = task.archived_at || now
      else
        changes.merge!(completed_at: nil, archived_at: nil)
      end
      task.update(changes)
      puts "#{task.name}\t#{task.task_status}"
    end

    def existing_path(path, directory: false)
      expanded = File.expand_path(path)
      valid = directory ? Dir.exist?(expanded) : File.file?(expanded)
      raise Error, "#{directory ? 'Directory' : 'File'} not found: #{expanded}" unless valid
      File.realpath(expanded)
    end

    def link_kind
      kind = @options.kind || 'general'
      raise Error, 'Link kind must be general, issue, or thread' unless %w[general issue thread].include?(kind)
      kind
    end

    def add_resource(group, target)
      task = select_task
      kind = group == 'link' ? link_kind : group
      if %w[directory file].include?(group)
        target = existing_path(target, directory: group == 'directory')
      else
        uri = URI.parse(target)
        raise Error, 'Use an absolute http or https URL' unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty?
      end
      raise Error, '--primary applies only to directories' if @options.primary && group != 'directory'
      Hiiro::DB.connection.transaction do
        resource = TaskResource.find_or_create(task_id: task.id, kind: kind, target: target) do |row|
          row.label = @options.label
          row.created_at = Time.now.iso8601
        end
        resource.update(label: @options.label) if @options.label
        task.update(primary_directory: target, updated_at: Time.now.iso8601) if @options.primary
        print_resource(resource)
      end
    rescue URI::InvalidURIError
      raise Error, 'Use an absolute http or https URL'
    end

    def resources(group, task)
      kinds = group == 'link' ? (@options.kind ? [link_kind] : %w[general issue thread pr]) : [group]
      task.resources.where(kind: kinds).all
    end

    def print_resource(resource)
      puts [resource.id, resource.kind, resource.label, resource.target].compact.join("\t")
    end

    def home_files(task)
      return [] unless Dir.exist?(task.home)
      raise Error, "Task home is a symlink: #{task.home}" if File.symlink?(task.home)
      Dir.glob('**/*', File::FNM_DOTMATCH, base: task.home).filter_map do |relative|
        path = File.join(task.home, relative)
        path if File.file?(path)
      end.sort
    end

    def list_resources(group, task)
      rows = resources(group, task)
      rows.each { |resource| print_resource(resource) }
      return unless group == 'file'
      registered = rows.map(&:target)
      home_files(task).each { |path| puts "home\t#{path}" unless registered.include?(File.realpath(path)) }
    end

    def open_resource(group, reference)
      task = select_task
      rows = resources(group, task)
      candidates = rows.map { |row| [row.target, [row.id.to_s, row.target, row.label].compact] }
      if group == 'file'
        candidates.concat(home_files(task).map { |path| [path, [path, path.delete_prefix(task.home + '/'), File.basename(path)]] })
      end
      matches = candidates.select { |_, names| reference.nil? || names.include?(reference) }.map(&:first).uniq
      raise Error, "No matching #{group}; run t #{group} list" if matches.empty?
      raise Error, "Ambiguous #{group}; use an ID or full path/URL" unless matches.one?
      path = matches.first
      existing_path(path, directory: group == 'directory') if %w[file directory].include?(group)
      open_default(path)
    end

    def doc_prefix(task)
      "task-#{task.id}-"
    end

    def new_doc(args)
      name = safe_name!(args.shift&.delete_suffix('.md'))
      task = select_task
      path = File.join(ensure_home(task), "#{doc_prefix(task)}#{name}.md")
      title = args.empty? ? name.tr('_-', ' ') : args.join(' ')
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |file| file.write("# #{title}\n\n") }
      puts path
    end

    def documents(task)
      home_files(task).select { |path| File.extname(path).downcase == '.md' }
    end

    def open_doc(reference)
      task = select_task
      matches = documents(task).select do |path|
        short_name = File.basename(path, '.md').delete_prefix(doc_prefix(task))
        reference.nil? || [path, path.delete_prefix(task.home + '/'), File.basename(path), File.basename(path, '.md'), short_name, "#{short_name}.md"].include?(reference)
      end
      raise Error, 'No matching document; run t doc list' if matches.empty?
      raise Error, 'Ambiguous document; use its relative or absolute path' unless matches.one?
      check_result(system('mdoc', matches.first), 'mdoc could not open the document; install mdoc and check its configuration')
    end

    def open_default(target)
      executable = RUBY_PLATFORM.include?('darwin') ? 'open' : 'xdg-open'
      check_result(system(executable, target), "#{executable} could not open #{target}")
    end

    def code_directory(task)
      task.primary_directory || (task.tree && (task.tree.start_with?('/') ? task.tree : File.join(Hiiro::WORK_DIR, task.tree)))
    end

    def workspace_label(task)
      (task.session || task.name).tr('.', '_')
    end

    def client
      @client ||= begin
        herdr = @hiiro.herdr_client
        unless herdr.server_running?
          raise Error, 'Herdr is not running; start Herdr for workspace/tab/pane commands, or use --task for task data'
        end
        herdr
      end
    end

    def workspace_for(task, required: true)
      label = workspace_label(task)
      collisions = TaskRecord.all_as_list.select { |candidate| workspace_label(candidate) == label }
      raise Error, "Workspace label #{label} is shared by tasks: #{collisions.map(&:name).join(', ')}" unless collisions.one?
      matches = client.workspaces.select { |workspace| workspace.name == label }
      raise Error, "Multiple Herdr workspaces have label #{label}" if matches.length > 1
      raise Error, 'Task workspace is not open; run t workspace open' if required && matches.empty?
      matches.first
    end

    def start_directory(task)
      path = @options.directory || code_directory(task) || ensure_home(task)
      existing_path(path, directory: true)
    end

    def open_workspace
      task = select_task
      workspace = workspace_for(task, required: false)
      if workspace
        check_result(client.focus_workspace(workspace.id))
      else
        workspace = client.new_workspace(workspace_label(task), start_directory: start_directory(task), focus: true)
        check_result(workspace, 'Herdr did not create the workspace')
      end
      puts workspace
    end

    def show_workspace
      workspace = workspace_for(select_task)
      puts workspace
      client.tabs(workspace: workspace).each { |tab| puts "  #{tab}" }
      client.panes(workspace: workspace).each { |pane| puts "  #{pane}\t#{pane.cwd}" }
    end

    def live_item(items, reference)
      matches = items.select { |item| item.id == reference || item.name == reference }
      raise Error, "No tab/pane in this task workspace matches #{reference}" if matches.empty?
      raise Error, "Ambiguous tab/pane label #{reference}; use its live ID" unless matches.one?
      matches.first
    end

    def new_tab(label)
      task = select_task
      result = client.new_tab(name: label, workspace: workspace_for(task), start_directory: start_directory(task), command: @options.command, focus: true)
      check_result(result['tab'], 'Herdr did not create the tab')
      puts result['tab']['tab_id']
    end

    def pane_action(action, args)
      reference = args.shift || raise(Error, 'A pane ID or label is required')
      task = select_task
      pane = live_item(client.panes(workspace: workspace_for(task)), reference)
      no_args!(args) unless action == 'run'
      case action
      when 'open'
        check_result(client.focus_pane(pane.id))
      when 'read'
        text = client.read_pane(pane.id)
        check_result(text, 'Herdr could not read the pane')
        puts text
      when 'split'
        raise Error, 'Split direction must be right or down' unless %w[right down].include?(@options.direction)
        created = client.split_pane(direction: @options.direction, target: pane.id, start_directory: start_directory(task), command: @options.command, focus: true)
        check_result(created, 'Herdr did not split the pane')
        puts created
      when 'run'
        raise Error, 'A command is required' if args.empty?
        check_result(client.run_in_pane(pane.id, args.shelljoin))
      end
    end

    def check_result(result, message = 'Herdr command failed')
      raise Error, message unless result
    end
  end
end
