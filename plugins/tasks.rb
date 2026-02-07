require 'yaml'
require 'fileutils'

WORK_DIR = File.join(Dir.home, 'work')
REPO_PATH = File.join(WORK_DIR, '.bare')

class TmuxSession
  attr_reader :name

  def self.current
    return nil unless ENV['TMUX']

    name = `tmux display-message -p '#S'`.chomp
    new(name)
  end

  def self.all
    output = `tmux list-sessions -F '#S' 2>/dev/null`
    output.lines(chomp: true).map { |name| new(name) }
  end

  def initialize(name)
    @name = name
  end

  def ==(other)
    other.is_a?(TmuxSession) && name == other.name
  end

  def to_s
    name
  end
end

class Tree
  attr_reader :path, :head, :branch

  def self.all(repo_path: REPO_PATH)
    output = `git -C #{repo_path} worktree list --porcelain 2>/dev/null`

    trees = []
    current = nil

    output.lines(chomp: true).each do |line|
      case line
      when /^worktree (.*)/
        trees << new(**current) if current
        current = { path: $1 }
      when /^HEAD (.*)/
        current[:head] = $1 if current
      when /^branch refs\/heads\/(.*)/
        current[:branch] = $1 if current
      when 'bare'
        current = nil
      end
    end

    trees << new(**current) if current
    trees
  end

  def initialize(path:, head: nil, branch: nil)
    @path = path
    @head = head
    @branch = branch
  end

  def name
    @name ||= if path.start_with?(WORK_DIR + '/')
      path.sub(WORK_DIR + '/', '')
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

  def ==(other)
    other.is_a?(Task) && name == other.name
  end

  def to_s
    name
  end

  def to_h
    h = { 'name' => name }
    h['tree'] = tree_name if tree_name
    h['session'] = session_name if session_name != name
    h
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
    @all_sessions ||= TmuxSession.all
  end

  def all_trees
    @all_trees ||= Tree.all
  end

  def all_apps
    @all_apps ||= config.apps
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
    @session ||= TmuxSession.current
  end

  def tree
    @tree ||= all_trees.find { |t| t.match?(path) }
  end

  def find_task(abbreviated)
    return nil if abbreviated.nil?

    if abbreviated.include?('/')
      parent_prefix, child_prefix = abbreviated.split('/', 2)
      parent = all_tasks.select(&:top_level?).find { |t| t.name.start_with?(parent_prefix) }
      return nil unless parent

      subtask = all_tasks.select { |t| t.parent_name == parent.name }.find { |t| t.short_name.start_with?(child_prefix) }
      return subtask if subtask

      # "main" refers to the parent task itself
      return parent if 'main'.start_with?(child_prefix)

      nil
    else
      all_tasks.find { |t| t.name.start_with?(abbreviated) }
    end
  end

  def find_tree(abbreviated)
    return nil if abbreviated.nil?
    all_trees.find { |t| t.name.start_with?(abbreviated) }
  end

  def find_session(abbreviated)
    return nil if abbreviated.nil?
    all_sessions.find { |s| s.name.start_with?(abbreviated) }
  end

  def find_app(abbreviated)
    return nil if abbreviated.nil?
    all_apps.find { |a| a.name.start_with?(abbreviated) }
  end
end

class TaskManager
  TASKS_DIR = File.join(Dir.home, '.config', 'hiiro', 'tasks')
  APPS_FILE = File.join(Dir.home, '.config', 'hiiro', 'apps.yml')

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
      data['tasks'] << task.to_h
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

      # Load from individual task_*.yml files
      task_files = Dir.glob(File.join(File.dirname(tasks_file), 'task_*.yml'))
      if task_files.any?
        tasks = task_files.map do |file|
          short_name = File.basename(file, '.yml').sub(/^task_/, '')
          data = YAML.safe_load_file(file) || {}
          # Support parent key for subtasks, or infer from tree path
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

  def task_by_name(name)
    return slash_lookup(name) if name.include?('/')

    tasks.find { |t|
      match_name = (scope == :subtask) ? t.short_name : t.name
      match_name.start_with?(name)
    }
  end

  def task_by_tree(tree_name)
    tasks.find { |t| t.tree_name == tree_name }
  end

  def task_by_session(session_name)
    tasks.find { |t| t.session_name == session_name }
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

    target_path = File.join(WORK_DIR, subtree_name)

    available = find_available_tree
    if available
      puts "Renaming worktree '#{available.name}' to '#{subtree_name}'..."
      FileUtils.mkdir_p(File.dirname(target_path))
      unless system('git', '-C', REPO_PATH, 'worktree', 'move', available.path, target_path)
        puts "ERROR: Failed to rename worktree"
        return
      end
    else
      puts "Creating new worktree '#{subtree_name}'..."
      FileUtils.mkdir_p(File.dirname(target_path))
      unless system('git', '-C', REPO_PATH, 'worktree', 'add', '--detach', target_path)
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
    tree_path = tree ? tree.path : File.join(WORK_DIR, task.tree_name)

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
    # Also remove any subtasks
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

    items.each do |task|
      marker = (current && current.name == task.name) ? "*" : " "
      tree = environment.find_tree(task.tree_name)
      branch = tree&.branch || (tree&.detached? ? '(detached)' : nil)
      branch_str = branch ? "  [#{branch}]" : ""

      display_name = scope == :subtask ? task.short_name : task.name
      puts format("%s %-25s  tree: %-20s%s", marker, display_name, task.tree_name || '(none)', branch_str)

      # Show subtask count for top-level tasks
      if scope == :task
        subs = subtasks(task)
        subs.each do |st|
          sub_marker = (current && current.name == st.name) ? "*" : " "
          sub_tree = environment.find_tree(st.tree_name)
          sub_branch = sub_tree&.branch || (sub_tree&.detached? ? '(detached)' : nil)
          sub_branch_str = sub_branch ? "  [#{sub_branch}]" : ""
          padding = " " * task.name.length
          puts format("%s %s/%-*s  tree: %-20s%s", sub_marker, padding, 25 - task.name.length - 1, st.short_name, st.tree_name || '(none)', sub_branch_str)
        end
      end
    end

    available = environment.all_trees.reject { |t|
      environment.all_tasks.any? { |task| task.tree_name == t.name }
    }

    if available.any?
      puts
      available.each do |tree|
        branch_str = tree.branch ? "  [#{tree.branch}]" : tree.detached? ? "  [(detached)]" : ""
        puts format("  %-25s  (available)%s", tree.name, branch_str)
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

  def cd_to_task(task)
    unless task
      puts "Task not found"
      return
    end

    tree = environment.find_tree(task.tree_name)
    path = tree ? tree.path : File.join(WORK_DIR, task.tree_name)
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
      send_cd(tree&.path || File.join(WORK_DIR, task.tree_name))
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
      tree&.path || File.join(WORK_DIR, task.tree_name)
    else
      `git rev-parse --show-toplevel`.strip
    end

    if app_name.nil?
      print tree_root
      return
    end

    matches = environment.all_apps.select { |a| a.name.start_with?(app_name) }

    case matches.count
    when 0
      puts "ERROR: No matches found"
      puts
      puts "Possible Apps:"
      environment.all_apps.each { |a| puts format("  %-20s => %s", a.name, a.relative_path) }
    when 1
      print matches.first.resolve(tree_root)
    else
      puts "Multiple matches found:"
      matches.each { |a| puts format("  %-20s => %s", a.name, a.relative_path) }
    end
  end

  def help
    scope_name = scope.to_s
    puts "Usage: h #{scope_name} <subcommand> [args]"
    puts
    puts "Subcommands:"
    puts "  list, ls              List #{scope_name}s"
    puts "  start NAME [APP]      Start a new #{scope_name}"
    puts "  switch [NAME]         Switch to a #{scope_name} (interactive if no name)"
    puts "  app [APP_NAME]        Open app in new tmux window (interactive if no name)"
    puts "  apps                  List configured apps"
    puts "  cd [APP_NAME]         Change directory to app"
    puts "  path [APP_NAME]       Print app path"
    puts "  status, st            Show current #{scope_name} status"
    puts "  save                  Save current session state"
    puts "  stop [NAME]           Stop a #{scope_name} (interactive if no name)"
  end

  # --- Interactive selection with sk ---

  def select_task_interactive(prompt = nil)
    names = if scope == :subtask
      tasks.map(&:short_name)
    else
      environment.all_tasks.map(&:name)
    end
    return nil if names.empty?

    sk_select(names.sort)
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
    tree_root = tree ? tree.path : File.join(WORK_DIR, task.tree_name)

    matches = environment.all_apps.select { |a| a.name.start_with?(app_name) }

    case matches.count
    when 0
      # Fallback: directory discovery
      exact = File.join(tree_root, app_name)
      return [app_name, exact] if Dir.exist?(exact)

      nested = File.join(tree_root, app_name, app_name)
      return [app_name, nested] if Dir.exist?(nested)

      puts "ERROR: App '#{app_name}' not found"
      list_apps
      nil
    when 1
      app = matches.first
      [app.name, app.resolve(tree_root)]
    else
      exact = matches.find { |a| a.name == app_name }
      if exact
        [exact.name, exact.resolve(tree_root)]
      else
        puts "ERROR: '#{app_name}' matches multiple apps:"
        matches.each { |a| puts "  #{a.name}" }
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

  def sk_select(items)
    Hiiro::Sk.select(items)
  end
end

module Tasks
  def self.load(hiiro)
    hiiro.load_plugin(Tmux)
    add_subcommands(hiiro)
  end

  def self.add_subcommands(hiiro)
    hiiro.add_subcmd(:task) do |*args|
      mgr = TaskManager.new(hiiro, scope: :task)
      task_hiiro = Tasks.build_hiiro(hiiro, mgr)
      task_hiiro.run
    end

    hiiro.add_subcmd(:subtask) do |*args|
      mgr = TaskManager.new(hiiro, scope: :subtask)
      task_hiiro = Tasks.build_hiiro(hiiro, mgr)
      task_hiiro.run
    end
  end

  def self.build_hiiro(parent_hiiro, mgr)
    bin_name = [parent_hiiro.bin, parent_hiiro.subcmd || ''].join('-')

    Hiiro.init(bin_name:, args: parent_hiiro.args) do |h|
      h.add_subcmd(:list) { mgr.list }
      h.add_subcmd(:ls) { mgr.list }

      h.add_subcmd(:start) do |task_name, app_name=nil|
        mgr.start_task(task_name, app_name: app_name)
      end

      h.add_subcmd(:switch) do |task_name=nil, app_name=nil|
        if task_name.nil?
          task_name = mgr.select_task_interactive
          next unless task_name
        end
        task = mgr.task_by_name(task_name)
        mgr.switch_to_task(task, app_name: app_name)
      end

      h.add_subcmd(:app) do |app_name=nil|
        if app_name.nil?
          names = mgr.environment.all_apps.map(&:name)
          app_name = mgr.send(:sk_select, names)
          next unless app_name
        end
        mgr.open_app(app_name)
      end

      h.add_subcmd(:apps) { mgr.list_apps }

      h.add_subcmd(:cd) do |app_name=nil|
        mgr.cd_to_app(app_name)
      end

      h.add_subcmd(:path) do |app_name=nil|
        mgr.app_path(app_name)
      end

      h.add_subcmd(:status) { mgr.status }
      h.add_subcmd(:st) { mgr.status }

      h.add_subcmd(:save) { mgr.save }

      h.add_subcmd(:stop) do |task_name=nil|
        if task_name.nil?
          task_name = mgr.select_task_interactive
          next unless task_name
        end
        task = mgr.task_by_name(task_name)
        mgr.stop_task(task)
      end

      h.add_subcmd(:edit) do
        system(ENV['EDITOR'] || 'nvim', __FILE__)
      end
    end
  end
end
