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

    def start_task(name, app_name: nil)
      existing = task_by_name(name)
      if existing
        puts "Task '#{existing.name}' already exists. Switching..."
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

    def available_trees
      assigned_tree_names = environment.all_tasks.map(&:tree_name)
      environment.all_trees.reject { |tree| assigned_tree_names.include?(tree.name) }
    end

    def list_label
      label = scope == :subtask ? "Subtasks" : "Tasks"
      if scope == :subtask && current_task
        parent = current_parent_task
        label = "Subtasks of '#{parent&.name}'" if parent
      end
      label
    end

    def status_info
      task = current_task
      return nil unless task

      tree = environment.find_tree(task.tree_name)
      {
        name: task.name,
        tree_name: task.tree_name,
        path: tree&.path,
        session_name: task.session_name,
        parent_name: task.subtask? ? task.parent_name : nil,
      }
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

    def all_apps
      environment.all_apps
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

      task_list.each do |task|
        display_name = scope == :subtask ? task.short_name : task.name
        line = task.display_line(scope: scope, environment: environment)
        mapping[line] = { type: :task, name: display_name }
      end

      # Add non-task tmux sessions (exclude sessions that belong to tasks)
      if scope == :task
        task_session_names = environment.all_tasks.map(&:session_name)
        extra_sessions = environment.all_sessions.reject { |s| task_session_names.include?(s.name) }
        extra_sessions.sort_by(&:name).each do |session|
          line = format("%-25s  (tmux session)", session.name)
          mapping[line] = { type: :session, name: session.name }
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

        nil
      when 1
        app = result.first.item
        [app.name, app.resolve(tree_root)]
      else
        exact = result.matches.find { |m| m.item.name == app_name }
        if exact
          [exact.item.name, exact.item.resolve(tree_root)]
        else
          nil
        end
      end
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
end
