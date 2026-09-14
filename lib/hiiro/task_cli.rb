require 'fileutils'
require 'time'
require 'uri'
require 'shellwords'

class Hiiro
  # Task CLI behind the `t`, `tt`, and `h task` executables.
  #
  #   Hiiro.run(*ARGV, external_commands: false, builtin_commands: false) { Hiiro::TaskCli.setup(self) }
  #
  # Grammar: `t COMMAND [TASK] [ARGS...]`. Commands that act on a task read it from
  # the first positional argument when that word names a task (exact or unique
  # prefix); otherwise the current task is used and the word stays in the payload.
  # `-t TASK` forces a task, `-f` picks one with a fuzzy finder, `.` is the current
  # task, and `-` selects orphan todos in todo commands.
  class TaskCli
    def self.setup(hiiro)
      hiiro.extend(Commands)
      hiiro.root_commands
    end

    # `tt ARGS...` is `t todo ARGS...`.
    def self.setup_todo(hiiro)
      hiiro.extend(Commands)
      hiiro.add_default do |*todo_args|
        hiiro.run_child(:todo, todo_args, external_commands: false, builtin_commands: false) do
          extend Commands
          todo_commands
        end
      end
    end

    module Commands
      class Error < Hiiro::Error; end

      TASK_OPTIONS = %i[task find].freeze

      def task_options
        add_option :task, short: :t, desc: 'Task name (exact or unique prefix)'
        add_flag :find, short: :f, desc: 'Choose the task with a fuzzy finder'
      end

      # Exact name, else unique prefix. An ambiguous prefix opens the fuzzy finder
      # over the candidates on a TTY and fails otherwise. nil when nothing matches.
      def lookup_task(reference)
        result = Hiiro::Matcher.new(Hiiro::TaskRecord.all_as_list, :name).by_prefix(reference.to_s)
        match = result.resolved
        return match.item if match
        return nil unless result.ambiguous?
        candidates = result.matches.map(&:item)
        raise Error, "Ambiguous task #{reference}: #{candidates.map(&:name).join(', ')}" unless $stdin.tty?
        pick_task(candidates)
      end

      def pick_task(candidates)
        raise Error, 'No tasks; create one with t new NAME' if candidates.empty?
        name = fuzzyfind(candidates.map(&:name))
        raise Error, 'No task selected' if name.nil? || name.strip.empty?
        candidates.find { |task| task.name == name.strip } || raise(Error, "No task named #{name.strip}")
      end

      def lookup_task!(reference)
        lookup_task(reference) || raise(Error, "Task not found: #{reference}; run t new #{reference}")
      end

      # Current task from Herdr, directory, or the saved pin. With no context at all,
      # a TTY gets the fuzzy finder over every task; ambiguous or stale context still fails.
      def current_task
        Hiiro::CurrentTask.new(herdr: -> { herdr_client }, pin: true).resolve!
      rescue Hiiro::Error => e
        raise unless $stdin.tty? && e.message.start_with?('No current task')
        pick_task(Hiiro::TaskRecord.all_as_list)
      end

      # Old h task rule: [task, remaining_args]. The first positional is the task
      # when it names one; otherwise the current task is used and args are untouched.
      # `.` is the current task. With orphan: true, `-` yields a nil task (orphan todos).
      # Passthrough commands pass options: nil and get -t/-f parsed from the raw args.
      def take_task(args, orphan: false, options: opts)
        args = args.dup
        forced = options&.fetch(:task)
        find = options&.fetch(:find)
        if options.nil?
          if %w[-t --task].include?(args.first) && args.length > 1
            args.shift
            forced = args.shift
          elsif args.first.to_s.start_with?('--task=')
            forced = args.shift.delete_prefix('--task=')
          elsif %w[-f --find].include?(args.first)
            args.shift
            find = true
          end
        end
        return [lookup_task!(forced), args] if forced
        return [pick_task(Hiiro::TaskRecord.all_as_list), args] if find
        first = args.first
        if first == '.'
          args.shift
          return [current_task, args]
        elsif first == '-' && orphan
          args.shift
          return [nil, args]
        elsif first && !first.start_with?('-') && (task = lookup_task(first))
          args.shift
          return [task, args]
        end
        [current_task, args]
      end

      def take_task_only(args, options: opts)
        task, rest = take_task(args, options: options)
        no_args!(rest)
        task
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

      # Live Herdr workspaces, or [] when Herdr is not running.
      def live_workspaces
        herdr_client.server_running? ? client.workspaces.to_a : []
      rescue Hiiro::Error
        []
      end

      # Tasks with open todo counts, an @ marker when the task workspace is open,
      # then any live Herdr workspaces that belong to no task.
      def list_tasks
        tasks = Hiiro::TaskRecord.all_as_list
        workspaces = live_workspaces
        labels = tasks.map { |task| workspace_label(task) }
        open_labels = workspaces.map(&:name)
        loose = workspaces.reject { |workspace| labels.include?(workspace.name) }
        if tasks.empty? && loose.empty?
          puts 'No tasks. Create one with t new NAME.'
          return
        end
        counts = open_todo_counts
        attached = tasks.any? { |task| open_labels.include?(workspace_label(task)) }
        rows = tasks.map do |task|
          count = counts[task.name]
          label = count.zero? ? task.name : "#{task.name} (#{count})"
          label = "#{open_labels.include?(workspace_label(task)) ? '@' : ' '} #{label}" if attached
          detail = []
          detail << "next: #{task.next_action}" if task.next_action
          detail << "waiting: #{task.waiting_on}" if task.waiting_on
          [label, task.task_status, detail.join('  ')]
        end
        name_col = rows.map { |row| row[0].length }.max || 0
        status_col = rows.map { |row| row[1].length }.max || 0
        rows.each { |label, status, detail| puts format("%-#{name_col}s  %-#{status_col}s  %s", label, status, detail).rstrip }
        return if loose.empty?
        puts unless rows.empty?
        puts 'Workspaces without a task:'
        loose.each { |workspace| puts "  #{workspace.name}  #{workspace.id}" }
      end


      def task_todos(task)
        return Hiiro::TodoItem.where(task_name: nil, subtask_name: nil).order(:id) unless task
        Hiiro::TodoItem.where(task_name: task.name, subtask_name: nil)
          .or(Sequel.join([:task_name, :subtask_name], '/') => task.name)
          .order(:id)
      end

      def add_todo(task, args)
        text = args.join(' ')
        raise Error, 'Usage: t todo add [TASK] TEXT...; todo text cannot be blank' if text.strip.empty?
        item = Hiiro::TodoItem.create(text: text, task_name: task&.name)
        puts "Added todo #{item.id} to #{task&.name || '-'}: #{item.text}"
      end

      def remove_todo(task, args)
        id = single(args)
        raise Error, 'Todo ID must be an exact decimal ID from t todo' unless id.match?(/\A\d+\z/)
        deleted = task_todos(task).where(id: id.to_i).delete
        name = task&.name || '-'
        raise Error, "Todo #{id} does not belong to task #{name}" unless deleted == 1
        puts "Removed todo #{id} from #{name}"
      end

      def list_todos(task, plain: false)
        task_todos(task).each { |item| puts plain ? item.text : "Todo #{item.id} [#{item.status}]: #{item.text}" }
      end

      def find_todo(task, args)
        id = single(args)
        raise Error, 'Todo ID must be an exact decimal ID from t todo' unless id.match?(/\A\d+\z/)
        item = task_todos(task).where(id: id.to_i).first
        raise Error, "Todo #{id} does not belong to task #{task&.name || '-'}" unless item
        item
      end

      def show_todo(task, args)
        puts find_todo(task, args).text
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

      def metadata(task, field, args)
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

      def add_resource(task, group, target)
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

      def open_resource(task, group, reference)
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

      def new_doc(task, args)
        name = safe_name!(args.shift&.delete_suffix('.md'))
        path = File.join(ensure_home(task), "#{doc_prefix(task)}#{name}.md")
        title = args.empty? ? name.tr('_-', ' ') : args.join(' ')
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |file| file.write("# #{title}\n\n") }
        puts path
      end

      def documents(task)
        home_files(task).select { |path| File.extname(path).downcase == '.md' }
      end

      def open_doc(task, reference)
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
        raise Error, "Task workspace is not open; run t switch #{task.name}" if required && matches.empty?
        matches.first
      end

      def start_directory(task)
        path = opts&.fetch(:directory) || code_directory(task) || ensure_home(task)
        existing_path(path, directory: true)
      end

      def open_workspace(task, save:)
        open_task_workspace(task, start_directory(task))
        save_current(task) if save
      end

      # Focus the task workspace or create it at directory. With optional: true,
      # a stopped Herdr prints a hint instead of failing (used after worktree changes).
      def open_task_workspace(task, directory, optional: false)
        if optional && !herdr_client.server_running?
          puts "Herdr is not running; run t switch #{task.name} to open the workspace"
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

      # --- switch targets: tasks plus live Herdr workspaces that are not task workspaces ---

      def loose_workspaces
        return [] unless herdr_client.server_running?
        labels = Hiiro::TaskRecord.all_as_list.map { |task| workspace_label(task) }
        client.workspaces.reject { |workspace| labels.include?(workspace.name) }
      end

      # Fuzzy map over tasks and loose workspaces; duplicate workspace names are numbered
      # in the label only, so the choice still maps to the exact workspace.
      def pick_switch_target(tasks, workspaces)
        raise Error, 'No tasks or workspaces to choose from' if tasks.empty? && workspaces.empty?
        counts = workspaces.group_by(&:name).transform_values(&:length)
        seen = Hash.new(0)
        map = tasks.to_h { |task| [task.name, task] }
        workspaces.each do |workspace|
          seen[workspace.name] += 1
          label = counts[workspace.name] > 1 ? "#{workspace.name} ##{seen[workspace.name]}" : workspace.name
          map["#{label} (workspace)"] = workspace
        end
        fuzzyfind_from_map(map) || raise(Error, 'Nothing selected')
      end

      # [target, explicit]. A task wins over a workspace with the same name.
      def switch_target(args)
        args = args.dup
        return [lookup_task!(opts.task), true] if opts.task
        return [pick_switch_target(Hiiro::TaskRecord.all_as_list, loose_workspaces), true] if opts.find
        first = args.first
        if first && first != '.' && !first.start_with?('-')
          args.shift
          no_args!(args)
          tasks = Hiiro::TaskRecord.all_as_list
          workspaces = loose_workspaces
          exact = tasks.find { |task| task.name == first }
          return [exact, true] if exact
          exact_ws = workspaces.select { |workspace| workspace.name == first }
          return [exact_ws.first, false] if exact_ws.one?
          task_matches = tasks.select { |task| task.name.start_with?(first) }
          ws_matches = exact_ws.any? ? exact_ws : workspaces.select { |workspace| workspace.name.start_with?(first) }
          return [task_matches.first, true] if task_matches.one? && ws_matches.empty?
          return [ws_matches.first, false] if ws_matches.one? && task_matches.empty?
          raise Error, "No task or workspace matches #{first}" if task_matches.empty? && ws_matches.empty?
          names = (task_matches.map(&:name) + ws_matches.map { |w| "#{w.name} (workspace)" }).join(', ')
          raise Error, "Ambiguous #{first}: #{names}" unless $stdin.tty?
          target = pick_switch_target(task_matches, ws_matches)
          return [target, target.is_a?(Hiiro::TaskRecord)]
        end
        args.shift if first == '.'
        no_args!(args)
        begin
          [Hiiro::CurrentTask.new(herdr: -> { herdr_client }, pin: true).resolve!, false]
        rescue Hiiro::Error => e
          raise unless $stdin.tty? && e.message.start_with?('No current task')
          target = pick_switch_target(Hiiro::TaskRecord.all_as_list, loose_workspaces)
          [target, target.is_a?(Hiiro::TaskRecord)]
        end
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
        raise Error, "No worktree for #{task.name}; run t tree new #{task.name}" unless task.tree
        puts "#{task.tree}\t#{tree_path(task)}"
      end

      # tree new [NAME]: NAME may be an existing task, a new task to create, or absent (current task).
      def new_tree(args, app_name, sparse_groups)
        task = if args.empty? then current_task
               elsif (found = lookup_task(args.first)) then found
               else create(safe_name!(args.first))
               end
        no_args!(args.drop(1))
        raise Error, "#{task.name} already has worktree #{task.tree}; run t tree rm #{task.name} first" if task.tree
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

      def resume_tree(task, reference)
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

      def show_workspace(task)
        workspace = workspace_for(task)
        puts workspace
        client.tabs(workspace: workspace).each { |tab| puts "  #{tab}" }
        client.panes(workspace: workspace).each { |pane| puts "  #{pane}\t#{pane.cwd}" }
      end

      def live_item(kind, items, reference)
        choose(kind, items.map { |item| [item, [item.id, item.name].compact] }, reference, hint: 'use its live ID')
      end

      def new_tab(task, label)
        result = client.new_tab(name: label, workspace: workspace_for(task), start_directory: start_directory(task), command: opts.command, focus: true)
        check_result(result['tab'], 'Herdr did not create the tab')
        puts result['tab']['tab_id']
      end

      def pane_action(task, action, args)
        reference = args.shift
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
          args.shift if args.first == '--'
          raise Error, 'A command is required' if args.empty?
          check_result(client.run_in_pane(pane.id, args.shelljoin))
        end
      end

      def check_result(result, message = 'Herdr command failed')
        raise Error, message unless result
      end

      def run_ai(task, tool, argv)
        directory = start_directory(task)
        workspace = workspace_for(task, required: false)
        workspace ||= client.new_workspace(workspace_label(task), start_directory: directory, focus: true)
        check_result(workspace, 'Herdr did not create the workspace')
        puts Hiiro::TaskSessions.new(client, workspace: workspace, directory: directory).run(tool, argv)
      end

      def child(name, child_args, &block)
        run_child(name, child_args, external_commands: false, builtin_commands: false) do
          extend Commands
          instance_eval(&block)
        end
      end

      def root_commands
        task_options
        add_default { |*unexpected| no_args!(unexpected); list_tasks }
        add_cmd(:help) { help }
        add_cmd(:list, :ls) { no_args!(opts.args); list_tasks }
        add_cmd(:show, args: ['task?'], opts: TASK_OPTIONS) { show(take_task_only(opts.args)) }
        add_cmd(:current, args: ['task?'], opts: TASK_OPTIONS) { puts take_task_only(opts.args).name }
        add_cmd(:use, :pin, args: %i[task], opts: TASK_OPTIONS) do
          task = take_task_only(opts.args)
          save_current(task)
          puts task.name
        end
        add_cmd(:new, args: %i[name]) { create(single(opts.args)) }
        add_cmd(:next, args: ['task?', 'text...'], opts: [*TASK_OPTIONS, :clear]) do
          task, rest = take_task(opts.args)
          metadata(task, :next_action, rest)
        end
        add_cmd(:waiting, args: ['task?', 'text...'], opts: [*TASK_OPTIONS, :clear]) do
          task, rest = take_task(opts.args)
          metadata(task, :waiting_on, rest)
        end
        add_cmd(:status, args: ['task?', 'state?'], opts: TASK_OPTIONS) do
          task, rest = take_task(opts.args)
          state = single(rest, optional: true)
          state ? set_status(task, state) : puts(task.task_status)
        end
        %w[done archive].each do |name|
          add_cmd(name, args: ['task?'], opts: TASK_OPTIONS) do
            set_status(take_task_only(opts.args), name == 'archive' ? 'archived' : 'done')
          end
        end

        add_cmd(:todo, args: ['command?'], passthrough: true) { child(:todo, args) { todo_commands } }

        %w[directory link pr file].each do |group|
          add_cmd(group, args: %i[command], passthrough: true) { child(group, args) { resource_commands(group) } }
        end

        add_cmd(:doc, args: %i[command], passthrough: true) do
          child(:doc, args) do
            task_options
            add_cmd(:help) { help }
            add_cmd(:new, args: ['task?', 'name', 'title...'], opts: TASK_OPTIONS) do
              task, rest = take_task(opts.args)
              new_doc(task, rest)
            end
            add_cmd(:list, :ls, args: ['task?'], opts: TASK_OPTIONS) { documents(take_task_only(opts.args)).each { |path| puts path } }
            add_cmd(:open, args: ['task?', 'name?'], opts: TASK_OPTIONS) do
              task, rest = take_task(opts.args)
              open_doc(task, single(rest, optional: true))
            end
          end
        end

        add_cmd(:tree, args: ['command?'], passthrough: true) do
          child(:tree, args) do
            task_options
            add_option :app, desc: 'App directory to open in the workspace'
            add_option :sparse, desc: 'Sparse checkout group (repeatable)', multi: true
            add_default { |*rest| show_tree(take_task_only(rest, options: nil)) }
            add_cmd(:help) { help }
            add_cmd(:new, args: ['name?'], opts: [*TASK_OPTIONS, :app, :sparse]) do
              if opts.task || opts.find
                new_tree([take_task_only(opts.args).name], opts.app, opts.sparse)
              else
                new_tree(opts.args, opts.app, opts.sparse)
              end
            end
            add_cmd(:rm, :remove, args: ['task?'], opts: TASK_OPTIONS) { remove_tree(take_task_only(opts.args)) }
            add_cmd(:resume, args: ['task?', 'worktree?'], opts: TASK_OPTIONS) do
              task, rest = take_task(opts.args)
              resume_tree(task, single(rest, optional: true))
            end
          end
        end

        add_cmd(:path, args: ['task?'], opts: TASK_OPTIONS) { puts start_directory(take_task_only(opts.args)) }
        add_cmd(:branch, args: ['task?'], opts: TASK_OPTIONS) { puts current_branch(take_task_only(opts.args)) }
        add_cmd(:cd, args: ['task?'], opts: TASK_OPTIONS) { cd_to(take_task_only(opts.args)) }
        add_cmd(:sh, args: ['task?', 'command...'], passthrough: true) do
          task, rest = take_task(args, options: nil)
          run_shell(task, rest)
        end

        add_option :directory, desc: 'Existing start directory'
        add_cmd(:switch, :workspace, args: ['task-or-workspace?'], opts: [*TASK_OPTIONS, :directory, :show]) do
          target, explicit = switch_target(opts.args)
          if target.is_a?(Hiiro::Herdr::Workspace)
            raise Error, '--show applies to task workspaces' if opts.show
            check_result(client.focus_workspace(target.id))
            puts target
          else
            opts.show ? show_workspace(target) : open_workspace(target, save: explicit)
          end
        end

        [%w[omp], %w[codex cdx], %w[claude cld]].each do |names|
          add_cmd(*names, args: ['task?', 'cli-args...'], passthrough: true) do
            task, rest = take_task(args, options: nil)
            run_ai(task, names.first, rest)
          end
        end

        add_cmd(:tab, args: %i[command], passthrough: true) do
          child(:tab, args) do
            task_options
            add_option :directory, desc: 'Existing start directory'
            add_option :command, desc: 'Command to run in the new tab'
            add_cmd(:help) { help }
            add_cmd(:list, :ls, args: ['task?'], opts: TASK_OPTIONS) do
              client.tabs(workspace: workspace_for(take_task_only(opts.args))).each { |tab| puts tab }
            end
            add_cmd(:new, args: ['task?', 'label?'], opts: [*TASK_OPTIONS, :directory, :command]) do
              task, rest = take_task(opts.args)
              new_tab(task, single(rest, optional: true))
            end
            add_cmd(:open, args: ['task?', 'reference?'], opts: TASK_OPTIONS) do
              task, rest = take_task(opts.args)
              workspace = workspace_for(task)
              tab = live_item('tab', client.tabs(workspace: workspace), single(rest, optional: true))
              check_result(client.focus_workspace(workspace.id))
              check_result(client.focus_tab(tab.id))
            end
          end
        end

        add_cmd(:pane, args: %i[command], passthrough: true) do
          child(:pane, args) do
            task_options
            add_option :directory, desc: 'Existing start directory'
            add_option :command, desc: 'Command to run in the new pane'
            add_option :direction, default: 'right', desc: 'Split direction: right or down'
            add_cmd(:help) { help }
            add_cmd(:list, :ls, args: ['task?'], opts: TASK_OPTIONS) do
              client.panes(workspace: workspace_for(take_task_only(opts.args))).each { |pane| puts pane }
            end
            %w[open read].each do |action|
              add_cmd(action, args: ['task?', 'pane?'], opts: TASK_OPTIONS) do
                task, rest = take_task(opts.args)
                pane_action(task, action, rest)
              end
            end
            add_cmd(:run, args: ['task?', 'pane', 'command...'], passthrough: true) do
              task, rest = take_task(args, options: nil)
              pane_action(task, 'run', rest)
            end
            add_cmd(:split, args: ['task?', 'pane'], opts: [*TASK_OPTIONS, :directory, :command, :direction]) do
              task, rest = take_task(opts.args)
              pane_action(task, 'split', rest)
            end
          end
        end
      end

      def todo_commands
        task_options
        add_option :plain, type: :flag, desc: 'Print only todo text, one per line'
        add_default do |*rest|
          task, rest = take_task(rest, orphan: true, options: nil)
          no_args!(rest)
          list_todos(task)
        end
        add_cmd(:help) { help }
        add_cmd(:list, :ls, args: ['task?'], opts: [*TASK_OPTIONS, :plain]) do
          task, rest = take_task(opts.args, orphan: true)
          no_args!(rest)
          list_todos(task, plain: opts.plain)
        end
        add_cmd(:show, args: ['task?', 'id'], opts: TASK_OPTIONS) do
          task, rest = take_task(opts.args, orphan: true)
          show_todo(task, rest)
        end
        add_cmd(:add, args: ['task?', 'text...'], passthrough: true) do
          task, rest = %w[-h --help].include?(args.first) ? [nil, args] : take_task(args, orphan: true, options: nil)
          if %w[-h --help].include?(rest.first)
            puts options.select(TASK_OPTIONS).parse([]).help_text
          else
            add_todo(task, rest)
          end
        end
        add_cmd(:rm, args: ['task?', 'id'], opts: TASK_OPTIONS) do
          task, rest = take_task(opts.args, orphan: true)
          remove_todo(task, rest)
        end
      end

      def resource_commands(group)
        task_options
        add_option :label, desc: 'Resource label'
        add_option :kind, desc: 'Link kind: general, issue, or thread' if group == 'link'
        add_options = [*TASK_OPTIONS, :label]
        add_options << :primary if group == 'directory'
        add_options << :kind if group == 'link'
        read_options = group == 'link' ? [*TASK_OPTIONS, :kind] : TASK_OPTIONS
        add_cmd(:help) { help }
        add_cmd(:add, args: ['task?', 'target'], opts: add_options) do
          task, rest = take_task(opts.args)
          add_resource(task, group, single(rest))
        end
        add_cmd(:list, :ls, args: ['task?'], opts: read_options) { list_resources(group, take_task_only(opts.args)) }
        add_cmd(:open, args: ['task?', 'reference?'], opts: read_options) do
          task, rest = take_task(opts.args)
          open_resource(task, group, single(rest, optional: true))
        end
      end
    end
  end
end
