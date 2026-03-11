require 'yaml'
require 'fileutils'

class Hiiro
  class TaskManager
    TASKS_DIR = File.join(Dir.home, '.config', 'hiiro', 'tasks')
    APPS_FILE = File.join(Dir.home, '.config', 'hiiro', 'apps.yml')

    attr_reader :hiiro, :scope, :environment

    def initialize(hiiro, scope: :task, environment: nil)
      @hiiro = hiiro
      @scope = scope
      @environment = environment || Environment.current
    end

    def config
      environment.config
    end

    # --- Scope-aware queries ---

    def tasks
      if scope == :subtask
        parent = current_parent_task
        return [] unless parent
        main_task = Task.new(name: "#{parent.name}/main", tree: parent.tree_name, session: parent.session_name)
        subtask_list = environment.all_tasks.select { |t| t.parent_name == parent.name }
        [main_task, *subtask_list]
      else
        environment.all_tasks.select(&:top_level?)
      end
    end

    def subtasks(task)
      environment.all_tasks.select { |t| t.parent_name == task.name }
    end

    def task_by_service_info(info)
      if name = info['task']
        task_by_name(name)
      elsif session = info['tmux_session']
        task_by_session(session)
      elsif tree = info['tree']
        task_by_tree(tree)
      end
    end

    def task_by_name(name)
      return slash_lookup(name) if name.include?('/')

      key = (scope == :subtask) ? :short_name : :name
      Hiiro::Matcher.new(tasks, key).by_prefix(name).first&.item
    end

    def task_by_tree(tree_name)
      environment.task_matcher.resolve(tree_name, :tree_name).resolved&.item
    end

    def task_by_session(session_name)
      environment.task_matcher.resolve(session_name, :session_name).resolved&.item
    end

    def current_task
      environment.task
    end

    def current_session
      environment.session
    end

    def current_tree
      environment.tree
    end

    # --- Actions ---

    def start_task(name, app_name: nil, sparse_groups: [])
      existing = task_by_name(name)
      if existing
        puts "Task '#{existing.name}' already exists. Switching..."
        tree_path = existing.tree&.path
        if tree_path
          if sparse_groups.any?
            apply_sparse_checkout(tree_path, sparse_groups)
          else
            Hiiro::Git.new(nil, tree_path).disable_sparse_checkout(tree_path)
          end
        end
        switch_to_task(existing, app_name: app_name)
        return
      end

      task_name = scope == :subtask ? "#{current_parent_task.name}/#{name}" : name
      subtree_name = scope == :subtask ? "#{current_parent_task.name}/#{name}" : "#{name}/main"

      target_path = File.join(Hiiro::WORK_DIR, subtree_name)

      git = Hiiro::Git.new(nil, Hiiro::REPO_PATH)
      available = find_available_tree
      if available
        puts "Renaming worktree '#{available.name}' to '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.move_worktree(available.path, target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to rename worktree"
          return
        end
      else
        puts "Creating new worktree '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.add_worktree_detached(target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to create worktree"
          return
        end
      end

      apply_sparse_checkout(target_path, sparse_groups) if sparse_groups.any?

      session_name = task_name
      task = Task.new(name: task_name, tree: subtree_name, session: session_name)
      config.save_task(task)

      base_dir = target_path
      if app_name
        app = environment.find_app(app_name)
        base_dir = app.resolve(target_path) if app
      end

      Dir.chdir(base_dir)
      hiiro.start_tmux_session(session_name)

      puts "Started task '#{task_name}' in worktree '#{subtree_name}'"
    end

    def switch_to_task(task, app_name: nil)
      unless task
        puts "Task not found"
        return
      end

      tree = environment.find_tree(task.tree_name)
      tree_path = tree ? tree.path : File.join(Hiiro::WORK_DIR, task.tree_name)

      session_name = task.session_name
      session_exists = system('tmux', 'has-session', '-t', session_name, err: File::NULL)

      if session_exists
        hiiro.start_tmux_session(session_name)
      else
        base_dir = tree_path
        if app_name
          app = environment.find_app(app_name)
          base_dir = app.resolve(tree_path) if app
        end

        if Dir.exist?(base_dir)
          Dir.chdir(base_dir)
          hiiro.start_tmux_session(session_name)
        else
          puts "ERROR: Path '#{base_dir}' does not exist"
          return
        end
      end

      puts "Switched to '#{task.name}'"
    end

    def stop_task(task)
      unless task
        puts "Task not found"
        return
      end

      config.remove_task(task.name)
      subtasks(task).each { |st| config.remove_task(st.name) }

      puts "Stopped task '#{task.name}' (worktree available for reuse)"
    end

    def list
      items = tasks
      if items.empty?
        puts scope == :subtask ? "No subtasks found" : "No tasks found"
        puts "Use 'h #{scope} start NAME' to create one."
        return
      end

      current = current_task
      label = scope == :subtask ? "Subtasks" : "Tasks"
      if scope == :subtask && current
        parent = current_parent_task
        label = "Subtasks of '#{parent&.name}'" if parent
      end

      puts "#{label}:"
      puts

      client_map = Hiiro::Tmux::Session.client_map

      # Collect rows as {prefix, name, tree, branch, session} so we can
      # compute max column widths before rendering.
      rows = []
      items.each do |task|
        marker = (current && current.name == task.name) ? "*" : " "
        attach = client_map.key?(task.session_name) ? "@" : " "
        rows << { prefix: "#{marker}#{attach} ", **task.display_data(scope: scope, environment: environment) }

        if scope == :task
          subtasks(task).each do |st|
            sub_marker = (current && current.name == st.name) ? "*" : " "
            sub_attach = client_map.key?(st.session_name) ? "@" : " "
            rows << { prefix: "#{sub_marker}#{sub_attach} - ", **st.display_data(scope: :subtask, environment: environment) }
          end
        end
      end

      # Column widths: the name column absorbs the variable-length prefix so
      # that tree/branch/session always start at the same position.
      name_col   = rows.map { |r| r[:prefix].length + r[:name].length }.max
      tree_col   = rows.map { |r| r[:tree].length }.max
      branch_col = rows.map { |r| r[:branch].length }.max

      rows.each do |r|
        name_pad = name_col - r[:prefix].length
        print r[:prefix]
        puts format("%-#{name_pad}s  %-#{tree_col}s  %-#{branch_col}s  %s",
                    r[:name], r[:tree], r[:branch], r[:session])
      end

      available = environment.all_trees.reject { |t|
        environment.all_tasks.any? { |task| task.tree_name == t.name }
      }

      if available.any?
        puts
        avail_name_col = [available.map { |t| t.name.length }.max, name_col].max
        available.each do |tree|
          branch_str = tree.branch ? "[#{tree.branch}]" : tree.detached? ? "[(detached)]" : ""
          puts format("  %-#{avail_name_col}s  (available)  %s", tree.name, branch_str).rstrip
        end
      end

      if scope == :task
        task_session_names = environment.all_tasks.map(&:session_name)
        extra_sessions = environment.all_sessions.reject { |s| task_session_names.include?(s.name) }
        if extra_sessions.any?
          puts
          extra_name_col = [extra_sessions.map { |s| s.name.length }.max, name_col].max
          extra_sessions.sort_by(&:name).each do |session|
            attach = client_map.key?(session.name) ? "@" : " "
            puts format(" %s %-#{extra_name_col}s  (tmux session)", attach, session.name)
          end
        end
      end
    end

    def status
      task = current_task
      unless task
        puts "Not currently in a task session"
        return
      end

      puts "Task: #{task.name}"
      puts "Worktree: #{task.tree_name}"
      tree = environment.find_tree(task.tree_name)
      puts "Path: #{tree&.path || '(unknown)'}"
      puts "Session: #{task.session_name}"
      puts "Parent: #{task.parent_name}" if task.subtask?
    end

    def save
      task = current_task
      unless task
        puts "ERROR: Not currently in a task session"
        return
      end

      windows = capture_tmux_windows(task.session_name)
      puts "Saved task '#{task.name}' state (#{windows.count} windows)"
    end

    def open_app(app_name)
      task = current_task
      unless task
        puts "ERROR: Not currently in a task session"
        return
      end

      result = resolve_app(app_name, task)
      return unless result

      resolved_name, app_path = result
      system('tmux', 'new-window', '-n', resolved_name, '-c', app_path)
      puts "Opened '#{resolved_name}' in new window (#{app_path})"
    end

    def list_apps
      apps = environment.all_apps
      if apps.any?
        puts "Configured apps:"
        puts
        apps.each do |app|
          puts format("  %-20s => %s", app.name, app.relative_path)
        end
      else
        puts "No apps configured."
        puts "Create #{APPS_FILE} with format:"
        puts "  app_name: relative/path/from/repo"
      end
    end

    def branch(task_name = nil)
      if task_name.nil?
        branch = select_branch_interactive
        return unless branch
        print branch
        return
      end

      task = task_by_name(task_name)
      unless task
        puts "Task not found: #{task_name}"
        return
      end

      if task.branch
        print task.branch
      elsif task.tree&.detached?
        puts "(detached HEAD)"
      else
        puts "(no branch)"
      end
    end

    def cd_to_task(task)
      unless task
        puts "Task not found"
        return
      end

      tree = environment.find_tree(task.tree_name)
      path = tree ? tree.path : File.join(Hiiro::WORK_DIR, task.tree_name)
      send_cd(path)
    end

    def cd_to_app(app_name = nil)
      task = current_task
      unless task
        puts "ERROR: Not currently in a task session"
        return
      end

      if app_name.nil? || app_name.empty?
        tree = environment.find_tree(task.tree_name)
        send_cd(tree&.path || File.join(Hiiro::WORK_DIR, task.tree_name))
        return
      end

      result = resolve_app(app_name, task)
      return unless result

      _resolved_name, app_path = result
      send_cd(app_path)
    end

    def app_path(app_name = nil)
      task = current_task
      tree_root = if task
        tree = environment.find_tree(task.tree_name)
        tree&.path || File.join(Hiiro::WORK_DIR, task.tree_name)
      else
        Hiiro::Git.new(nil, Dir.pwd).root
      end

      if app_name.nil?
        print tree_root
        return
      end

      result = environment.app_matcher.find_all(app_name)

      case result.count
      when 0
        puts "ERROR: No matches found"
        puts
        puts "Possible Apps:"
        environment.all_apps.each { |a| puts format("  %-20s => %s", a.name, a.relative_path) }
      when 1
        print result.first.item.resolve(tree_root)
      else
        puts "Multiple matches found:"
        result.matches.each { |m| puts format("  %-20s => %s", m.item.name, m.item.relative_path) }
      end
    end

    # --- Interactive selection with sk ---

    def select_task_interactive(prompt = nil)
      task_list = if scope == :subtask
        tasks.sort_by(&:short_name)
      else
        environment.all_tasks.sort_by(&:name)
      end

      mapping = {}

      all_data = task_list.map { |t| [t, t.display_data(scope: scope, environment: environment)] }
      name_col   = all_data.map { |_, d| d[:name].length }.max || 0
      tree_col   = all_data.map { |_, d| d[:tree].length }.max || 0
      branch_col = all_data.map { |_, d| d[:branch].length }.max || 0

      all_data.each do |task, d|
        line = format("%-#{name_col}s  %-#{tree_col}s  %-#{branch_col}s  %s",
                      d[:name], d[:tree], d[:branch], d[:session])
        mapping[line] = task
      end

      # Add non-task tmux sessions (exclude sessions that belong to tasks)
      if scope == :task
        task_session_names = environment.all_tasks.map(&:session_name)
        extra_sessions = environment.all_sessions.reject { |s| task_session_names.include?(s.name) }
        extra_sessions.sort_by(&:name).each do |session|
          line = format("%-25s  (tmux session)", session.name)
          mapping[line] = session
        end
      end

      return nil if mapping.empty?

      selected = hiiro.fuzzyfind_from_map(mapping)
      selected
    end

    def value_for_task(task_name = nil, &block)
      if task_name
        task = task_by_name(task_name)
        return block.call(task) if task
      end

      task_list = scope == :subtask ? tasks.sort_by(&:short_name) : environment.all_tasks.sort_by(&:name)

      mapping = task_list.each_with_object({}) do |task, h|
        name = scope == :subtask ? task.short_name : task.name
        val = block.call(task)&.to_s

        line = format("%-25s  | %s", name, val)
        h[line] = val
      end

      hiiro.fuzzyfind_from_map(mapping)
    end

    def select_branch_interactive(prompt = nil)
      name_map = if scope == :subtask
        tasks.sort_by(&:short_name).each_with_object({}) { |t, h| h[format('%-25s  | %s', t.short_name, t.branch)] = t.branch }
      else
        environment.all_tasks.sort_by(&:name).each_with_object({}) { |t, h| h[format('%-25s  | %s', t.name, t.branch)] = t.branch }
      end
      return nil if name_map.empty?

      hiiro.fuzzyfind_from_map(name_map)
    end

    # --- Private helpers ---

    private

    def slash_lookup(input)
      environment.find_task(input)
    end

    def current_parent_task
      task = current_task
      return nil unless task

      if task.subtask?
        environment.find_task(task.parent_name)
      else
        task
      end
    end

    def find_available_tree
      assigned_tree_names = environment.all_tasks.map(&:tree_name)
      environment.all_trees.find { |tree| !assigned_tree_names.include?(tree.name) }
    end

    def resolve_app(app_name, task)
      tree = environment.find_tree(task.tree_name)
      tree_root = tree ? tree.path : File.join(Hiiro::WORK_DIR, task.tree_name)

      result = environment.app_matcher.find_all(app_name)

      case result.count
      when 0
        exact = File.join(tree_root, app_name)
        return [app_name, exact] if Dir.exist?(exact)

        nested = File.join(tree_root, app_name, app_name)
        return [app_name, nested] if Dir.exist?(nested)

        puts "ERROR: App '#{app_name}' not found"
        list_apps
        nil
      when 1
        app = result.first.item
        [app.name, app.resolve(tree_root)]
      else
        exact = result.matches.find { |m| m.item.name == app_name }
        if exact
          [exact.item.name, exact.item.resolve(tree_root)]
        else
          puts "ERROR: '#{app_name}' matches multiple apps:"
          result.matches.each { |m| puts "  #{m.item.name}" }
          nil
        end
      end
    end

    def apply_sparse_checkout(path, group_names)
      dirs = SparseGroups.dirs_for_groups(group_names)
      if dirs.empty?
        puts "WARNING: No directories found for sparse groups: #{group_names.join(', ')}"
        return
      end
      puts "Applying sparse checkout (groups: #{group_names.join(', ')})..."
      Hiiro::Git.new(nil, path).sparse_checkout(path, dirs)
    end

    def send_cd(path)
      pane = ENV['TMUX_PANE']
      if pane
        system('tmux', 'send-keys', '-t', pane, "cd #{path}\n")
      else
        system('tmux', 'send-keys', "cd #{path}\n")
      end
    end

    def capture_tmux_windows(session)
      output = `tmux list-windows -t #{session} -F '\#{window_index}:\#{window_name}:\#{pane_current_path}' 2>/dev/null`
      output.lines.map(&:strip).map { |line|
        idx, name, path = line.split(':')
        { 'index' => idx, 'name' => name, 'path' => path }
      }
    end

    class Config
      attr_reader :tasks_file, :apps_file

      def initialize(tasks_file: nil, apps_file: nil)
        @tasks_file = tasks_file || File.join(TASKS_DIR, 'tasks.yml')
        @apps_file = apps_file || APPS_FILE
      end

      def tasks
        data = load_tasks
        (data['tasks'] || []).map { |h| Task.new(**h.transform_keys(&:to_sym)) }
      end

      def apps
        return [] unless File.exist?(apps_file)
        data = YAML.safe_load_file(apps_file) || {}
        data.map { |name, path| App.new(name: name, path: path) }
      end

      def save_task(task)
        data = load_tasks
        data['tasks'] ||= []
        data['tasks'].reject! { |t| t['name'] == task.name }
        data['tasks'] << task.to_h.transform_keys(&:to_s)
        save_tasks(data)
      end

      def remove_task(name)
        data = load_tasks
        data['tasks'] ||= []
        data['tasks'].reject! { |t| t['name'] == name }
        save_tasks(data)
      end

      private

      def load_tasks
        if File.exist?(tasks_file)
          return YAML.safe_load_file(tasks_file) || { 'tasks' => [] }
        end

        task_files = Dir.glob(File.join(File.dirname(tasks_file), 'task_*.yml'))
        if task_files.any?
          tasks = task_files.map do |file|
            short_name = File.basename(file, '.yml').sub(/^task_/, '')
            data = YAML.safe_load_file(file) || {}
            parent = data['parent']
            if parent.nil? && data['tree']&.include?('/')
              parent = data['tree'].split('/').first
            end
            name = parent ? "#{parent}/#{short_name}" : short_name
            h = { 'name' => name }
            h['tree'] = data['tree'] if data['tree']
            h['session'] = data['session'] if data['session']
            h
          end
          return { 'tasks' => tasks }
        end

        assignments_file = File.join(File.dirname(tasks_file), 'assignments.yml')
        if File.exist?(assignments_file)
          raw = YAML.safe_load_file(assignments_file) || {}
          tasks = raw.map do |tree_path, task_name|
            h = { 'name' => task_name, 'tree' => tree_path }
            h['session'] = task_name if task_name.include?('/')
            h
          end
          data = { 'tasks' => tasks }
          save_tasks(data)
          return data
        end

        { 'tasks' => [] }
      end

      def save_tasks(data)
        FileUtils.mkdir_p(File.dirname(tasks_file))
        File.write(tasks_file, YAML.dump(data))
      end
    end
  end

  class SparseGroups
    FILE = File.join(Dir.home, '.config', 'hiiro', 'sparse_groups.yml')

    def self.load(file: FILE)
      return {} unless File.exist?(file)
      YAML.safe_load_file(file) || {}
    end

    def self.dirs_for_groups(group_names, file: FILE)
      groups = load(file: file)
      group_names.flat_map { |name| Array(groups[name]) }.uniq
    end
  end

  module Tasks
    def self.build_hiiro(parent_hiiro, tm)
      task_hiiro = parent_hiiro.make_child do |h|
        h.add_subcmd(:list) { tm.list }
        h.add_subcmd(:ls) { tm.list }

        h.add_subcmd(:start) do |*raw_args|
          opts = Hiiro::Options.parse(raw_args) do
            option(:sparse, short: :s, desc: 'Sparse checkout group (may be repeated)', multi: true)
          end
          task_name = opts.args[0]
          app_name  = opts.args[1]
          tm.start_task(task_name, app_name: app_name, sparse_groups: opts.sparse)
        end

        h.add_subcmd(:switch) do |task_name=nil, app_name=nil|
          if task_name.nil?
            selected = tm.select_task_interactive
            next unless selected

            case selected
            when Hiiro::Tmux::Session
              h.start_tmux_session(selected.name)
              puts "Switched to session '#{selected.name}'"
              next
            when Hiiro::Task
              tm.switch_to_task(selected, app_name: app_name)
              next
            end
          end

          task = tm.task_by_name(task_name)

          # If no task found, check for a matching tmux session
          unless task
            session = tm.environment.find_session(task_name)
            if session
              h.start_tmux_session(session.name)
              puts "Switched to session '#{session.name}'"
              next
            end
          end

          tm.switch_to_task(task, app_name: app_name)
        end

        h.add_subcmd(:app) do |app_name=nil|
          if app_name.nil?
            names = tm.environment.all_apps.map(&:name)
            app_name = h.fuzzyfind(names)
            next unless app_name
          end
          tm.open_app(app_name)
        end

        h.add_subcmd(:apps) { tm.list_apps }

        h.add_subcmd(:cd) do |app_name=nil|
          tm.cd_to_app(app_name)
        end

        h.add_subcmd(:path) do |app_name=nil|
          tm.app_path(app_name)
        end

        h.add_subcmd(:branch) do |task_name=nil|
          print tm.value_for_task(task_name, &:branch)
        end

        h.add_subcmd(:tree) do |task_name=nil|
          print tm.value_for_task(task_name, &:tree_name)
        end

        h.add_subcmd(:session) do |task_name=nil|
          print tm.value_for_task(task_name, &:session_name)
        end

        h.add_subcmd(:current) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.name
        end

        h.add_subcmd(:cbranch) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.branch if task.branch
        end

        h.add_subcmd(:ctree) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.tree_name if task.tree_name
        end

        h.add_subcmd(:csession) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.session_name if task.session_name
        end

        h.add_subcmd(:status) { tm.status }
        h.add_subcmd(:st) { tm.status }

        h.add_subcmd(:save) { tm.save }

        h.add_subcmd(:stop) do |task_name=nil|
          if task_name.nil?
            selected = tm.select_task_interactive
            next unless selected
            task_name = selected.name
          end
          task = tm.task_by_name(task_name)
          tm.stop_task(task)
        end

        h.add_subcmd(:edit) do
          h.edit_files(__FILE__)
        end

        h.add_subcmd(:todo) do |*todo_args|
          todo_manager = Hiiro::TodoManager.new
          task = tm.current_task

          task_info = if task
            {
              task_name: task.name,
              tree: task.tree_name,
              branch: task.branch,
              session: task.session_name
            }
          end

          todo_subcmd = todo_args.shift
          case todo_subcmd
          when 'ls', 'list', nil
            show_all = todo_args.delete('-a') || todo_args.delete('--all')
            items = if show_all
              todo_manager.all
            elsif task
              todo_manager.filter_by_task(task.name).select { |i| %w[not_started started].include?(i.status) }
            else
              todo_manager.active
            end

            if items.empty?
              puts task ? "No todo items for task '#{task.name}'." : "No todo items found."
            else
              puts todo_manager.list(items)
            end

          when 'add'
            if todo_args.empty?
              new_items = todo_manager.edit_items(task_info: task_info)
              if new_items.empty?
                puts "No items added."
                next
              end
              todo_manager.add_items(new_items)
              if new_items.length == 1
                puts "Added: #{todo_manager.format_item(new_items.first)}"
              else
                puts "Added #{new_items.length} items:"
                new_items.each { |item| puts "  #{todo_manager.format_item(item)}" }
              end
              next
            end

            tags = nil
            text_parts = []
            while todo_args.any?
              arg = todo_args.shift
              case arg
              when '-t', '--tags'
                tags = todo_args.shift
              else
                text_parts << arg
              end
            end
            text = text_parts.join(' ')
            item = todo_manager.add(text, tags: tags, task_info: task_info)
            puts "Added: #{todo_manager.format_item(item)}"

          when 'rm', 'remove'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo rm <id|index>"
              next
            end
            item = todo_manager.remove(id_or_index)
            puts item ? "Removed: #{item.text}" : "Item not found: #{id_or_index}"

          when 'start'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo start <id|index>"
              next
            end
            item = todo_manager.start(id_or_index)
            puts item ? "Started: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'done'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo done <id|index>"
              next
            end
            item = todo_manager.done(id_or_index)
            puts item ? "Done: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'skip'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo skip <id|index>"
              next
            end
            item = todo_manager.skip(id_or_index)
            puts item ? "Skipped: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'search'
            query = todo_args.join(' ')
            if query.empty?
              puts "Usage: h #{tm.scope} todo search <query>"
              next
            end
            items = todo_manager.search(query)
            if items.empty?
              puts "No items matching: #{query}"
            else
              puts todo_manager.list(items)
            end

          else
            puts "Usage: h #{tm.scope} todo <ls|add|rm|start|done|skip|search> [args]"
          end
        end

        h.add_subcmd(:queue) do |*queue_args|
          task = tm.current_task
          task_info = if task
            {
              task_name: task.name,
              tree_name: task.tree_name,
              session_name: task.session_name
            }
          end

          q = Hiiro::Queue.current(parent_hiiro)
          Hiiro::Queue.build_hiiro(h, q, task_info: task_info).run
        end

        h.add_subcmd(:service) do |*svc_args|
          sm = Hiiro::ServiceManager.new
          Hiiro::ServiceManager.build_hiiro(h, sm, task_manager: tm).run
        end

        h.add_subcmd(:run) do |*run_args|
          rt = Hiiro::RunnerTool.new
          Hiiro::RunnerTool.build_hiiro(h, rt, git: parent_hiiro.git).run
        end

        h.add_subcmd(:file) do |*file_args|
          af = Hiiro::AppFiles.new
          Hiiro::AppFiles.build_hiiro(h, af, environment: tm.environment).run
        end
      end

      task_hiiro
    end
  end

  class Tree
    attr_reader :path, :head, :branch

    def self.all(repo_path: Hiiro::REPO_PATH)
      git = Hiiro::Git.new(nil, repo_path)
      git.worktrees(repo_path: repo_path).filter_map do |wt|
        next if wt.bare?
        new(path: wt.path, head: wt.head, branch: wt.branch)
      end
    end

    def initialize(path:, head: nil, branch: nil)
      @path = path
      @head = head
      @branch = branch
    end

    def name
      @name ||= if path.start_with?(Hiiro::WORK_DIR + '/')
        path.sub(Hiiro::WORK_DIR + '/', '')
      else
        File.basename(path)
      end
    end

    def match?(pwd = Dir.pwd)
      pwd == path || pwd.start_with?(path + '/')
    end

    def detached?
      branch.nil?
    end

    def ==(other)
      other.is_a?(Tree) && path == other.path
    end

    def to_s
      name
    end
  end

  class Task
    attr_reader :name, :tree_name, :session_name

    def initialize(name:, tree: nil, session: nil, **_)
      @name = name
      @tree_name = tree
      @session_name = session || name
    end

    def parent_name
      return nil unless subtask?
      name.split('/').first
    end

    def short_name
      subtask? ? name.split('/', 2).last : name
    end

    def subtask?
      name.include?('/')
    end

    def top_level?
      !subtask?
    end

    def tree
      @tree ||= Environment.current&.find_tree(tree_name)
    end

    def branch
      tree&.branch
    end

    def ==(other)
      other.is_a?(Task) && name == other.name
    end

    def to_s
      name
    end

    def to_h
      h = { name: name }
      h[:tree] = tree_name if tree_name
      h[:session] = session_name if session_name != name
      h
    end

    def display_data(scope: :task, environment:)
      display_name = (scope == :subtask) ? short_name : name
      tree = environment.find_tree(tree_name)
      branch = tree&.branch || (tree&.detached? ? '(detached)' : '(none)')
      sname = session_name || '(none)'
      {
        name:    display_name,
        tree:    tree_name || '(none)',
        branch:  "[#{branch}]",
        session: "(#{sname})"
      }
    end
  end

  class App
    attr_reader :name, :relative_path

    def initialize(name:, path:)
      @name = name
      @relative_path = path
    end

    def resolve(tree_root)
      File.join(tree_root, relative_path)
    end

    def ==(other)
      other.is_a?(App) && name == other.name
    end

    def to_s
      name
    end
  end

  class Environment
    attr_reader :path

    def self.current
      new(path: Dir.pwd)
    end

    def initialize(path: Dir.pwd, config: nil)
      @path = path
      @config = config
    end

    def config
      @config ||= TaskManager::Config.new
    end

    def all_tasks
      @all_tasks ||= config.tasks
    end

    def all_sessions
      @all_sessions ||= Hiiro::Tmux::Session.all
    end

    def all_trees
      @all_trees ||= Tree.all
    end

    def all_apps
      @all_apps ||= config.apps
    end

    def tree_matcher
      @tree_matcher ||= Hiiro::Matcher.new(all_trees, :name)
    end

    def session_matcher
      @session_matcher ||= Hiiro::Matcher.new(all_sessions, :name)
    end

    def app_matcher
      @app_matcher ||= Hiiro::Matcher.new(all_apps, :name)
    end

    def task_matcher
      @task_matcher ||= Hiiro::Matcher.new(all_tasks, :name)
    end

    def task
      @task ||= begin
        s = session
        t = tree
        all_tasks.find { |task|
          (s && task.session_name == s.name) ||
            (t && task.tree_name == t.name)
        }
      end
    end

    def session
      @session ||= Hiiro::Tmux::Session.current
    end

    def tree
      @tree ||= all_trees.find { |t| t.match?(path) }
    end

    def find_task(abbreviated)
      return nil if abbreviated.nil?

      if abbreviated.include?('/')
        result = task_matcher.resolve_path(abbreviated)
        return result.resolved&.item if result.match?

        parent_prefix, child_prefix = abbreviated.split('/', 2)
        if 'main'.start_with?(child_prefix)
          return task_matcher.find(parent_prefix).first&.item
        end

        nil
      else
        task_matcher.find(abbreviated).first&.item
      end
    end

    def find_tree(abbreviated)
      return nil if abbreviated.nil?
      tree_matcher.find(abbreviated).first&.item
    end

    def find_session(abbreviated)
      return nil if abbreviated.nil?
      session_matcher.find(abbreviated).first&.item
    end

    def find_app(abbreviated)
      return nil if abbreviated.nil?
      app_matcher.find(abbreviated).first&.item
    end
  end
end
