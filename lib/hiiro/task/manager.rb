require 'yaml'
require 'fileutils'

class Hiiro
  class TaskManager
    # Core task manager responsible for task lifecycle and resolution.
    # Handles task lookup, start/stop/switch operations, and app access.
    class Manager
      include Matchable

      # Define constants locally - they're also in Config for use there
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

      # --- Data Access ---

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

      def current_task
        environment.task
      end

      def current_session
        environment.session
      end

      def current_tree
        environment.tree
      end

      # --- Task Lookup ---

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

      def task_by_service_info(info)
        if name = info['task']
          task_by_name(name)
        elsif session = info['tmux_session']
          task_by_session(session)
        elsif tree = info['tree']
          task_by_tree(tree)
        end
      end

      # --- Path Resolution (noun-named per Phase 5) ---

      def task_path(task)
        tree = environment.find_tree(task.tree_name)
        tree ? tree.path : File.join(Hiiro::WORK_DIR, task.tree_name)
      end

      def app_path(app_name, task)
        resolution = AppResolution.new(environment, task)
        resolution.path_for(app_name)
      end

      def available_tree
        assigned_tree_names = environment.all_tasks.map(&:tree_name)
        environment.all_trees.find { |tree| !assigned_tree_names.include?(tree.name) }
      end

      # Backwards compatibility aliases
      alias_method :resolve_task_path, :task_path
      alias_method :resolve_app_path, :app_path
      alias_method :find_available_tree, :available_tree

      # --- High-Level Actions ---

      def start_task(name, app_name: nil)
        existing = task_by_name(name)
        if existing
          puts "Task '#{existing.name}' already exists. Switching..."
          switch_to_task(existing, app_name: app_name)
          return
        end

        start_action = TaskStart.new(self, name, app_name: app_name)
        start_action.call
      end

      def switch_to_task(task, app_name: nil)
        unless task
          puts "Task not found"
          return
        end

        task.switch(manager: self, app_name: app_name)
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

      def save
        task = current_task
        unless task
          puts "ERROR: Not currently in a task session"
          return
        end

        windows = tmux_windows(task.session_name)
        puts "Saved task '#{task.name}' state (#{windows.count} windows)"
      end

      def open_app(app_name)
        task = current_task
        unless task
          puts "ERROR: Not currently in a task session"
          return
        end

        result = app_path(app_name, task)
        return unless result

        resolved_name, path = result
        system('tmux', 'new-window', '-n', resolved_name, '-c', path)
        puts "Opened '#{resolved_name}' in new window (#{path})"
      end

      def cd_to_task(task)
        unless task
          puts "Task not found"
          return
        end

        path = task_path(task)
        send_cd(path)
      end

      def cd_to_app(app_name = nil)
        task = current_task
        unless task
          puts "ERROR: Not currently in a task session"
          return
        end

        if app_name.nil? || app_name.empty?
          send_cd(task_path(task))
          return
        end

        result = app_path(app_name, task)
        return unless result

        _resolved_name, path = result
        send_cd(path)
      end

      def branch(task_name = nil)
        if task_name.nil?
          branch_val = select_branch_interactive
          return unless branch_val
          print branch_val
          return
        end

        task = task_by_name(task_name)
        unless task
          puts "Task not found: #{task_name}"
          return
        end

        task_branch = task.branch(environment)
        if task_branch
          print task_branch
        elsif task.tree(environment)&.detached?
          puts "(detached HEAD)"
        else
          puts "(no branch)"
        end
      end

      def print_app_path(app_name = nil)
        task = current_task
        tree_root = if task
          task_path(task)
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

      # --- Interactive Selection ---

      def select_task_interactive(prompt = nil)
        selection = TaskSelection.new(self)
        selection.selected
      end

      def select_branch_interactive(prompt = nil)
        name_map = if scope == :subtask
          tasks.sort_by(&:short_name).each_with_object({}) { |t, h| h[format('%-25s  | %s', t.short_name, t.branch(environment))] = t.branch(environment) }
        else
          environment.all_tasks.sort_by(&:name).each_with_object({}) { |t, h| h[format('%-25s  | %s', t.name, t.branch(environment))] = t.branch(environment) }
        end
        return nil if name_map.empty?

        hiiro.fuzzyfind_from_map(name_map)
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

      # --- Presentation ---

      def list
        TaskPresenter.print_list(self)
      end

      def list_apps
        TaskPresenter.print_apps(environment.all_apps)
      end

      def status
        TaskPresenter.print_status(current_task, environment)
      end

      # --- Private Helpers ---

      private

      def slash_lookup(input)
        environment.find_task(input)
      end

      def current_parent_task
        task = current_task
        return nil unless task

        task.subtask? ? environment.find_task(task.parent_name) : task
      end

      def send_cd(path)
        pane = ENV['TMUX_PANE']
        if pane
          system('tmux', 'send-keys', '-t', pane, "cd #{path}\n")
        else
          system('tmux', 'send-keys', "cd #{path}\n")
        end
      end

      def tmux_windows(session)
        output = `tmux list-windows -t #{session} -F '\\#{window_index}:\\#{window_name}:\\#{pane_current_path}' 2>/dev/null`
        output.lines.map(&:strip).map { |line|
          idx, name, path = line.split(':')
          { 'index' => idx, 'name' => name, 'path' => path }
        }
      end

      # Backwards compatibility alias
      alias_method :capture_tmux_windows, :tmux_windows
      alias_method :app_path, :print_app_path
    end
  end
end
