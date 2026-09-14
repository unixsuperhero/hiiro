require 'fileutils'
require 'time'
require 'uri'
require 'shellwords'

class Hiiro
  # Task-first CLI behind the `t` and `tt` executables.
  #
  #   Hiiro.run(*ARGV, external_commands: false, builtin_commands: false) { Hiiro::TaskCli.setup(self) }
  #
  # Commands holds the helpers and the `add_cmd` declarations for each scope.
  class TaskCli
    def self.setup(hiiro)
      hiiro.extend(Commands)
      hiiro.add_default do |reference = nil, *command_args|
        if reference.nil? || %w[ls list].include?(reference)
          hiiro.no_args!(command_args)
          hiiro.list_tasks
        elsif reference == 'help'
          hiiro.no_args!(command_args)
          puts "Usage: t TASK [COMMAND ...]\n\nBare t, t ls, or t list lists tasks with open todo counts; t TASK shows one."
          puts "Use . for the current task, or - for unassigned todos."
          puts "Todo shortcut: tt TASK [COMMAND ...]\n\nTask commands:"
          hiiro.run_task_scope('TASK', ['help'])
        else
          hiiro.run_task_scope(reference, command_args)
        end
      end
    end

    # `tt [TASK] [COMMAND ...]` is `t TASK todo [COMMAND ...]` with `.` as the default task.
    def self.setup_todo(hiiro)
      hiiro.extend(Commands)
      hiiro.add_default do |reference = nil, *todo_args|
        if reference == 'help'
          hiiro.no_args!(todo_args)
          hiiro.run_task_scope('.', %w[todo help])
        else
          hiiro.run_task_scope(reference || '.', ['todo', *todo_args])
        end
      end
    end

    module Commands
      class Error < Hiiro::Error; end

      def selected_task_scope
        resolve(:task_scope)
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
        unless name && name.match?(%r{\A[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?\z}) && name.bytesize <= 120
          raise Error, 'Use a name of 1-120 ASCII letters, digits, dots, underscores, or hyphens, starting with a letter or digit; one / separates a subtask from its parent'
        end
        name
      end

      def select_task
        selected_task_scope.task!
      end

      def save_current(task)
        pin = Hiiro::PinRecord.find_key('t', 'current_task') || Hiiro::PinRecord.new(command: 't', key: 'current_task')
        pin.value = task.id
        pin.save
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
        record = Hiiro::TaskRecord.find_by_name(name)
        if record
          ensure_home(record)
          puts "Task already exists: #{name}\n#{record.home}"
          return record
        end
        now = Time.now.iso8601
        record = Hiiro::TaskRecord.new(name: name, session: name, status: 'active', created_at: now, updated_at: now)
        ensure_home(record)
        record.save
        puts "Created #{name}\n#{record.home}"
        record
      end

      def open_todo_counts
        Hiiro::TodoItem.exclude(task_name: nil).exclude(status: %w[done skip])
          .group_and_count(:task_name, :subtask_name).all
          .each_with_object(Hash.new(0)) do |row, counts|
            name = [row[:task_name], row[:subtask_name]].compact.join('/')
            counts[name] += row[:count]
          end
      end

      def list_tasks
        tasks = Hiiro::TaskRecord.all_as_list
        if tasks.empty?
          puts 'No tasks. Create one with t TASK new or t TASK todo add TEXT.'
          return
        end
        counts = open_todo_counts
        rows = tasks.map do |task|
          count = counts[task.name]
          label = count.zero? ? task.name : "#{task.name} (#{count})"
          detail = []
          detail << "next: #{task.next_action}" if task.next_action
          detail << "waiting: #{task.waiting_on}" if task.waiting_on
          [label, task.task_status, detail.join('  ')]
        end
        name_col = rows.map { |row| row[0].length }.max
        status_col = rows.map { |row| row[1].length }.max
        rows.each { |label, status, detail| puts format("%-#{name_col}s  %-#{status_col}s  %s", label, status, detail).rstrip }
      end


      def task_todos(task)
        return Hiiro::TodoItem.where(task_name: nil, subtask_name: nil).order(:id) unless task
        Hiiro::TodoItem.where(task_name: task.name, subtask_name: nil)
          .or(Sequel.join([:task_name, :subtask_name], '/') => task.name)
          .order(:id)
      end

      def add_todo(args)
        text = args.join(' ')
        raise Error, 'Usage: t TASK todo add TEXT...; todo text cannot be blank' if text.strip.empty?
        scope = selected_task_scope
        task, item = Hiiro::DB.connection.transaction(mode: :immediate) do
          selected = scope.task
          selected ||= create(scope.reference) unless scope.orphan?
          [selected, Hiiro::TodoItem.create(text: text, task_name: selected&.name)]
        end
        puts "Added todo #{item.id} to #{task&.name || '-'}: #{item.text}"
      end

      def remove_todo(args)
        id = single(args)
        raise Error, 'Todo ID must be an exact decimal ID from t TASK todo' unless id.match?(/\A\d+\z/)
        scope = selected_task_scope
        task = scope.orphan? ? nil : scope.task!
        deleted = task_todos(task).where(id: id.to_i).delete
        name = task&.name || '-'
        raise Error, "Todo #{id} does not belong to task #{name}" unless deleted == 1
        puts "Removed todo #{id} from #{name}"
      end

      def list_todos
        scope = selected_task_scope
        task = scope.orphan? ? nil : scope.task!
        task_todos(task).each { |item| puts "Todo #{item.id} [#{item.status}]: #{item.text}" }
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
        task_todos(task).each { |item| puts "Todo #{item.id} [#{item.status}]: #{item.text}" }
      end

      def metadata(field, args)
        task = select_task
        raise Error, 'Use text or --clear, not both' if opts.clear && !args.empty?
        if args.empty? && !opts.clear
          puts task[field] if task[field]
          return
        end
        text = opts.clear ? nil : args.join(' ')
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
        raise Error, "Status must be #{Hiiro::TaskRecord::STATUSES.join(', ')}" unless Hiiro::TaskRecord::STATUSES.include?(state)
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
        kind = opts.kind || 'general'
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
        raise Error, '--primary applies only to directories' if opts.fetch(:primary, false) && group != 'directory'
        Hiiro::DB.connection.transaction do
          resource = Hiiro::TaskResource.find_or_create(task_id: task.id, kind: kind, target: target) do |row|
            row.label = opts.label
            row.created_at = Time.now.iso8601
          end
          resource.update(label: opts.label) if opts.label
          task.update(primary_directory: target, updated_at: Time.now.iso8601) if opts.fetch(:primary, false)
          print_resource(resource)
        end
      rescue URI::InvalidURIError
        raise Error, 'Use an absolute http or https URL'
      end

      def resources(group, task)
        kinds = group == 'link' ? (opts.kind ? [link_kind] : %w[general issue thread pr]) : [group]
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

      # Pick one value from [[value, names], ...]: exact name, then unique prefix
      # via Hiiro::Matcher, or an interactive fuzzyfind when no reference is given.
      def choose(kind, candidates, reference, hint: 'use an ID or full path/URL')
        raise Error, "No #{kind} found" if candidates.empty?
        if reference.nil?
          return candidates.first.first if candidates.one?
          chosen = fuzzyfind_from_map(candidates.to_h { |value, names| [names.first, value] })
          return chosen if chosen
          raise Error, "No #{kind} selected"
        end
        exact = candidates.select { |_, names| names.include?(reference) }.map(&:first).uniq
        return exact.first if exact.one?
        raise Error, "Ambiguous #{kind} #{reference}; #{hint}" if exact.length > 1
        pairs = candidates.flat_map { |value, names| names.map { |name| [name, value] } }
        found = Hiiro::Matcher.by_prefix(pairs, reference) { |pair| pair.first }.matches.map { |m| m.item.last }.uniq
        raise Error, "No matching #{kind} #{reference}" if found.empty?
        raise Error, "Ambiguous #{kind} #{reference}; #{hint}" unless found.one?
        found.first
      end

      def open_resource(group, reference)
        task = select_task
        rows = resources(group, task)
        candidates = rows.map { |row| [row.target, [row.id.to_s, row.target, row.label].compact] }
        if group == 'file'
          candidates.concat(home_files(task).map { |path| [path, [path, path.delete_prefix(task.home + '/'), File.basename(path)]] })
        end
        path = choose(group, candidates, reference)
        existing_path(path, directory: group == 'directory') if %w[file directory].include?(group)
        check_result(open_default(path), "Could not open #{path}")
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
        candidates = documents(task).map do |path|
          short_name = File.basename(path, '.md').delete_prefix(doc_prefix(task))
          [path, [short_name, path.delete_prefix(task.home + '/'), File.basename(path), File.basename(path, '.md'), "#{short_name}.md", path]]
        end
        path = choose('document', candidates, reference, hint: 'use its relative or absolute path')
        check_result(system('mdoc', path), 'mdoc could not open the document; install mdoc and check its configuration')
      end

      def code_directory(task)
        task.primary_directory || (task.tree && (task.tree.start_with?('/') ? task.tree : File.join(Hiiro::WORK_DIR, task.tree)))
      end

      def workspace_label(task)
        (task.session || task.name).tr('.', '_')
      end

      def client
        @client ||= begin
          herdr = herdr_client
          unless herdr.server_running?
            raise Error, 'Herdr is not running; start Herdr for workspace/tab/pane commands, or supply a task name for task data'
          end
          herdr
        end
      end

      def workspace_for(task, required: true)
        label = workspace_label(task)
        collisions = Hiiro::TaskRecord.all_as_list.select { |candidate| workspace_label(candidate) == label }
        raise Error, "Workspace label #{label} is shared by tasks: #{collisions.map(&:name).join(', ')}" unless collisions.one?
        matches = client.workspaces.select { |workspace| workspace.name == label }
        raise Error, "Multiple Herdr workspaces have label #{label}" if matches.length > 1
        raise Error, "Task workspace is not open; run t #{task.name} switch" if required && matches.empty?
        matches.first
      end

      def start_directory(task)
        path = opts&.fetch(:directory) || code_directory(task) || ensure_home(task)
        existing_path(path, directory: true)
      end

      def open_workspace
        task = select_task
        open_task_workspace(task, start_directory(task))
        save_current(task) if selected_task_scope.explicit?
      end

      # Focus the task workspace or create it at directory. With optional: true,
      # a stopped Herdr prints a hint instead of failing (used after worktree changes).
      def open_task_workspace(task, directory, optional: false)
        if optional && !herdr_client.server_running?
          puts "Herdr is not running; run t #{task.name} switch to open the workspace"
          return
        end
        workspace = workspace_for(task, required: false)
        if workspace
          check_result(client.focus_workspace(workspace.id))
        else
          workspace = client.new_workspace(workspace_label(task), start_directory: directory, focus: true)
          check_result(workspace, 'Herdr did not create the workspace')
        end
        puts workspace
      end

      # --- Worktrees (shared with h task via Hiiro::TaskManager) ---

      def tree_manager
        @tree_manager ||= Hiiro::TaskManager.new(self)
      end

      def tree_path(task)
        return nil unless task.tree
        task.tree.start_with?('/') ? task.tree : File.join(Hiiro::WORK_DIR, task.tree)
      end

      def show_tree(task)
        raise Error, "No worktree for #{task.name}; run t #{task.name} tree new" unless task.tree
        puts "#{task.tree}\t#{tree_path(task)}"
      end

      def new_tree(app_name, sparse_groups)
        scope = selected_task_scope
        task = scope.explicit? ? (scope.task || create(scope.reference)) : scope.task!
        raise Error, "#{task.name} already has worktree #{task.tree}; run t #{task.name} tree rm first" if task.tree
        subtree = task.name.include?('/') ? task.name : "#{task.name}/main"
        path = tree_manager.create_tree(subtree, sparse_groups: Array(sparse_groups))
        raise Error, "Could not create worktree #{subtree}" unless path
        task.update(tree: subtree, session: task.session || task.name, updated_at: Time.now.iso8601)
        puts "Created worktree #{subtree}\n#{path}"
        directory = path
        if app_name
          app = Hiiro::Environment.current.find_app(app_name)
          raise Error, "Unknown app: #{app_name}" unless app
          directory = app.resolve(path)
        end
        open_task_workspace(task, directory, optional: true)
      end

      def remove_tree(task)
        raise Error, "#{task.name} has no worktree" unless task.tree
        tree = task.tree
        tree_manager.config.detach_tree(task.name)
        Hiiro::TaskRecord.subtasks_of(task.name).each { |sub| tree_manager.config.detach_tree(sub.name) if sub.tree }
        puts "Detached worktree #{tree} from #{task.name}; the directory stays for reuse or resume"
      end

      def resume_tree(reference)
        task = select_task
        raise Error, "#{task.name} already has worktree #{task.tree}" if task.tree
        used = Hiiro::TaskRecord.exclude(tree: nil).select_map(:tree)
        available = Hiiro::Tree.all.reject { |tree| used.include?(tree.name) || used.include?(tree.path) }
        tree = choose('worktree', available.map { |t| [t, [t.name, t.path]] }, reference, hint: 'use its full name')
        task.update(tree: tree.name, session: task.session || task.name, updated_at: Time.now.iso8601)
        puts "Resumed #{task.name} from worktree #{tree.name}"
        open_task_workspace(task, tree.path, optional: true)
      end

      def current_branch(task)
        path = tree_path(task)
        raise Error, "No worktree for #{task.name}" unless path && Dir.exist?(path)
        branch = Hiiro::Git.new(nil, path).branch.to_s
        branch.empty? || branch == 'HEAD' ? '(detached)' : branch
      end

      def run_shell(task, command)
        Dir.chdir(start_directory(task))
        command.empty? ? exec(ENV['SHELL'] || 'zsh') : exec(*command)
      end

      def cd_to(task)
        pane = ENV['HERDR_PANE_ID']
        raise Error, 'Not running inside a Herdr pane' unless pane
        check_result(client.run_in_pane(pane, "cd #{start_directory(task).shellescape}"))
      end

      def show_workspace
        workspace = workspace_for(select_task)
        puts workspace
        client.tabs(workspace: workspace).each { |tab| puts "  #{tab}" }
        client.panes(workspace: workspace).each { |pane| puts "  #{pane}\t#{pane.cwd}" }
      end

      def live_item(kind, items, reference)
        choose(kind, items.map { |item| [item, [item.id, item.name].compact] }, reference, hint: 'use its live ID')
      end

      def new_tab(label)
        task = select_task
        result = client.new_tab(name: label, workspace: workspace_for(task), start_directory: start_directory(task), command: opts.command, focus: true)
        check_result(result['tab'], 'Herdr did not create the tab')
        puts result['tab']['tab_id']
      end

      def pane_action(action, args)
        reference = args.shift
        task = select_task
        pane = live_item('pane', client.panes(workspace: workspace_for(task)), reference)
        no_args!(args) unless action == 'run'
        case action
        when 'open'
          check_result(client.focus_pane(pane.id))
        when 'read'
          text = client.read_pane(pane.id)
          check_result(text, 'Herdr could not read the pane')
          puts text
        when 'split'
          raise Error, 'Split direction must be right or down' unless %w[right down].include?(opts.direction)
          created = client.split_pane(direction: opts.direction, target: pane.id, start_directory: start_directory(task), command: opts.command, focus: true)
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

      def run_ai(tool, argv)
        task = select_task
        directory = start_directory(task)
        workspace = workspace_for(task, required: false)
        workspace ||= client.new_workspace(workspace_label(task), start_directory: directory, focus: true)
        check_result(workspace, 'Herdr did not create the workspace')
        puts Hiiro::TaskSessions.new(client, workspace: workspace, directory: directory).run(tool, argv)
      end

      def run_task_scope(reference, command_args)
        add_resolver(:task_scope, Hiiro::TaskScope.new(reference, herdr: -> { herdr_client }))
        run_child(reference, command_args, external_commands: false, builtin_commands: false) do
          extend Commands
          task_commands
        end
      end

      def task_commands
        add_default do |*unexpected|
          no_args!(unexpected)
          show(select_task)
        end
        add_cmd(:help) { help }
        add_cmd(:show) { no_args!(opts.args); show(select_task) }
        add_cmd(:current) do
          no_args!(opts.args)
          task = select_task
          save_current(task) if selected_task_scope.explicit?
          puts task.name
        end
        add_cmd(:new) { no_args!(opts.args); create(selected_task_scope.reference) }
        add_cmd(:next, args: ['text...'], opts: %i[clear]) { metadata(:next_action, opts.args) }
        add_cmd(:waiting, args: ['text...'], opts: %i[clear]) { metadata(:waiting_on, opts.args) }
        add_cmd(:status, args: ['state?']) do
          state = single(opts.args, optional: true)
          state ? set_status(select_task, state) : puts(select_task.task_status)
        end
        %w[done archive].each do |name|
          add_cmd(name) do
            no_args!(opts.args)
            set_status(select_task, name == 'archive' ? 'archived' : 'done')
          end
        end

        add_cmd(:todo, args: ['command?'], passthrough: true) do
          run_child(:todo, args, external_commands: false, builtin_commands: false) do
            extend Commands
            add_default { |*unexpected| no_args!(unexpected); list_todos }
            add_cmd(:help) { help }
            add_cmd(:list, :ls) { no_args!(opts.args); list_todos }
            add_cmd(:add, args: ['text...'], passthrough: true) do
              if %w[-h --help].include?(args.first)
                puts options.select([]).parse([]).help_text
              else
                add_todo(args)
              end
            end
            add_cmd(:rm, args: %i[id]) { remove_todo(opts.args) }
          end
        end

        %w[directory link pr file].each do |group|
          add_cmd(group, args: %i[command], passthrough: true) do
            run_child(group, args, external_commands: false, builtin_commands: false) do
              extend Commands
              add_option :label, desc: 'Resource label'
              add_option :kind, desc: 'Link kind: general, issue, or thread' if group == 'link'
              add_options = %i[label]
              add_options << :primary if group == 'directory'
              add_options << :kind if group == 'link'
              read_options = group == 'link' ? %i[kind] : []
              add_cmd(:help) { help }
              add_cmd(:add, args: %i[target], opts: add_options) { add_resource(group, single(opts.args)) }
              add_cmd(:list, :ls, opts: read_options) { no_args!(opts.args); list_resources(group, select_task) }
              add_cmd(:open, args: ['reference?'], opts: read_options) { open_resource(group, single(opts.args, optional: true)) }
            end
          end
        end

        add_cmd(:doc, args: %i[command], passthrough: true) do
          run_child(:doc, args, external_commands: false, builtin_commands: false) do
            extend Commands
            add_cmd(:help) { help }
            add_cmd(:new, args: ['name', 'title...']) { new_doc(opts.args) }
            add_cmd(:list, :ls) { no_args!(opts.args); documents(select_task).each { |path| puts path } }
            add_cmd(:open, args: ['name?']) { open_doc(single(opts.args, optional: true)) }
          end
        end

        add_cmd(:tree, args: ['command?'], passthrough: true) do
          run_child(:tree, args, external_commands: false, builtin_commands: false) do
            extend Commands
            add_option :app, desc: 'App directory to open in the workspace'
            add_option :sparse, desc: 'Sparse checkout group (repeatable)', multi: true
            add_default { |*unexpected| no_args!(unexpected); show_tree(select_task) }
            add_cmd(:help) { help }
            add_cmd(:new, opts: %i[app sparse]) { no_args!(opts.args); new_tree(opts.app, opts.sparse) }
            add_cmd(:rm, :remove) { no_args!(opts.args); remove_tree(select_task) }
            add_cmd(:resume, args: ['worktree?']) { resume_tree(single(opts.args, optional: true)) }
          end
        end

        add_cmd(:path) { no_args!(opts.args); puts start_directory(select_task) }
        add_cmd(:branch) { no_args!(opts.args); puts current_branch(select_task) }
        add_cmd(:cd) { no_args!(opts.args); cd_to(select_task) }
        add_cmd(:sh, args: ['command...'], passthrough: true) { run_shell(select_task, args) }

        add_option :directory, desc: 'Existing start directory'
        add_cmd(:switch, :workspace, opts: %i[directory show]) do
          no_args!(opts.args)
          opts.show ? show_workspace : open_workspace
        end

        [%w[omp], %w[codex cdx], %w[claude cld]].each do |names|
          add_cmd(*names, args: ['cli-args...'], passthrough: true) { run_ai(names.first, args) }
        end

        add_cmd(:tab, args: %i[command], passthrough: true) do
          run_child(:tab, args, external_commands: false, builtin_commands: false) do
            extend Commands
            add_option :directory, desc: 'Existing start directory'
            add_option :command, desc: 'Command to run in the new tab'
            add_cmd(:help) { help }
            add_cmd(:list, :ls) { no_args!(opts.args); client.tabs(workspace: workspace_for(select_task)).each { |tab| puts tab } }
            add_cmd(:new, args: ['label?'], opts: %i[directory command]) { new_tab(single(opts.args, optional: true)) }
            add_cmd(:open, args: ['reference?']) do
              reference = single(opts.args, optional: true)
              workspace = workspace_for(select_task)
              tab = live_item('tab', client.tabs(workspace: workspace), reference)
              check_result(client.focus_workspace(workspace.id))
              check_result(client.focus_tab(tab.id))
            end
          end
        end

        add_cmd(:pane, args: %i[command], passthrough: true) do
          run_child(:pane, args, external_commands: false, builtin_commands: false) do
            extend Commands
            add_option :directory, desc: 'Existing start directory'
            add_option :command, desc: 'Command to run in the new pane'
            add_option :direction, default: 'right', desc: 'Split direction: right or down'
            add_cmd(:help) { help }
            add_cmd(:list, :ls) { no_args!(opts.args); client.panes(workspace: workspace_for(select_task)).each { |pane| puts pane } }
            %w[open read].each do |action|
              add_cmd(action, args: ['pane?']) { pane_action(action, opts.args) }
            end
            add_cmd(:run, args: ['pane', 'command...']) { pane_action('run', opts.args) }
            add_cmd(:split, args: %i[pane], opts: %i[directory command direction]) { pane_action('split', opts.args) }
          end
        end
      end
    end
  end
end
