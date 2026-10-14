require 'yaml'
require 'fileutils'

class Hiiro
  class TaskManager

    attr_reader :hiiro, :scope, :environment

    def initialize(hiiro, scope: :task, environment: nil)
      @hiiro = hiiro
      @scope = scope
      @environment = environment || hiiro.environment
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

    def current_task
      environment.task
    end

    # Create (or reuse an unassigned) worktree under WORK_DIR and return its path,
    # or nil on failure. Used by `t TASK tree new`.
    def create_tree(subtree_name, sparse_groups: [])
      target_path = File.join(Hiiro::WORK_DIR, subtree_name)

      git = Hiiro::Git.new(nil, Hiiro::REPO_PATH)
      available = find_available_tree
      if available
        puts "Renaming worktree '#{available.name}' to '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.move_worktree(available.path, target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to rename worktree"
          return nil
        end
      else
        puts "Creating new worktree '#{subtree_name}'..."
        FileUtils.mkdir_p(File.dirname(target_path))
        unless git.add_worktree_detached(target_path, repo_path: Hiiro::REPO_PATH)
          puts "ERROR: Failed to create worktree"
          return nil
        end
      end

      apply_sparse_checkout(target_path, sparse_groups) if sparse_groups.any?
      target_path
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

    private

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

    class Config
      def tasks
        TaskRecord.all_as_list.map { |record| Task.new(id: record.id, **record.task_attributes) }
      end

      def apps
        AppRecord.all_as_hash.map { |name, path| App.new(name: name, path: path) }
      end

      def detach_tree(name)
        Hiiro::DB.connection.transaction(mode: :immediate) do
          record = TaskRecord.find_by_name(name)
          next unless record&.tree

          path = record.tree.start_with?('/') ? record.tree : File.join(Hiiro::WORK_DIR, record.tree)
          TaskResource.find_or_create(task_id: record.id, kind: 'directory', target: path)
          record.set(tree: nil, updated_at: Time.now.iso8601)
          record.save_changes
        end
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

  class Tree
    attr_reader :path, :head, :branch

    def self.from_path(path)
      expanded = File.expand_path(path.to_s)
      branch = Hiiro::Git.new(nil, expanded).branch if Dir.exist?(expanded)
      branch = nil if branch.nil? || branch.empty? || branch == 'HEAD'
      new(path: expanded, branch: branch)
    end

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
      @name ||= begin
        roots = [Hiiro::WORK_DIR]
        roots << File.realpath(Hiiro::WORK_DIR) if Dir.exist?(Hiiro::WORK_DIR)
        root = roots.uniq.find { |dir| path.start_with?(dir + '/') }
        root ? path.delete_prefix(root + '/') : File.basename(path)
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
    attr_reader :id, :name, :tree_name, :session_name, :color_index, :app, :created_at, *TaskRecord::METADATA_COLUMNS

    def initialize(name:, id: nil, tree: nil, session: nil, color_index: nil, **attributes)
      @id = id
      @name = name
      @tree_name = tree
      @session_name = session || name
      @color_index = color_index
      @attributes = attributes.slice(:app, :created_at, *TaskRecord::METADATA_COLUMNS)
      @attributes.each { |key, value| instance_variable_set("@#{key}", value) }
    end

    def home
      TaskRecord.home_for(name)
    end

    def parent_name
      return nil unless subtask?
      name.split('/').first
    end

    def short_name
      subtask? ? name.split('/', 2).last : name
    end

    def subtask?
      name.include?('/') && !absolute_tree?
    end

    def top_level?
      !subtask?
    end

    def absolute_tree?
      tree_name.to_s.start_with?('/')
    end

    def tree
      @tree ||= Environment.current&.find_tree(tree_name)
    end

    def branch
      tree&.branch
    end

    def path
      tree&.path
    end

    def ==(other)
      other.is_a?(Task) && name == other.name
    end

    def to_s
      name
    end

    def to_h
      h = @attributes.merge(name: name)
      h[:tree] = tree_name if tree_name
      h[:session] = session_name if session_name != name
      h[:color_index] = color_index unless color_index.nil?
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
    def path = @context.is_a?(TaskLocation) ? @context.invocation_directory : @path

    def self.current = new(path: Dir.pwd)

    def initialize(path: Dir.pwd, config: nil, context: nil, chooser: nil)
      @path = path
      @config = config
      @context = context
      @terminal = context.is_a?(TaskLocation) ? context.terminal : Herdr::Location.from_env
      @chooser = chooser || Hiiro.new('h').method(:fuzzyfind_from_map)
      @task_chooser = chooser || Picker.task_chooser
    end

    def context
      @context = @context.call if @context.respond_to?(:call)
      @context ||= CurrentTask.new(herdr: -> { Hiiro::Herdr.client }, cwd: path, pin: false, chooser: @task_chooser).context
    end

    def terminal = @context.is_a?(TaskLocation) ? @context.terminal : @terminal

    def resolved_context = (@context if @context.is_a?(TaskLocation))

    def config
      @config ||= TaskManager::Config.new
    end

    def all_tasks
      config.tasks
    end

    def all_sessions
      @all_sessions ||= Hiiro::Herdr.client.workspaces.to_a
    end

    def all_trees
      @all_trees ||= Tree.all
    end

    def all_apps
      config.apps
    end

    def tree_matcher
      @tree_matcher ||= Hiiro::Matcher.new(all_trees, :name)
    end

    def session_matcher
      @session_matcher ||= Hiiro::Matcher.new(all_sessions, :name)
    end

    def app_matcher
      Hiiro::Matcher.new(all_apps, :name)
    end

    def task_matcher
      Hiiro::Matcher.new(all_tasks, :name)
    end

    def task
      record = context.task
      record && all_tasks.find { |item| item.name == record.name }
    end

    def session
      terminal = context.terminal
      terminal.workspace_id && Hiiro::Herdr.client.get_workspace(terminal.workspace_id)
    end

    def tree
      directory = context.code_directory
      return Tree.from_path(directory) if directory && Dir.exist?(directory)
      matches = all_trees.select { |item| TaskLocation.contains?(item.path, path) }
      raise Error, "Ambiguous directory tree: #{matches.map(&:name).join(', ')}" if matches.length > 1
      matches.first
    end

    def find_task(abbreviated, chooser: @task_chooser, tty: $stdin.tty?)
      return nil if abbreviated.nil?
      raise Error, 'Task reference cannot be empty' if abbreviated.strip.empty?
      result = abbreviated.include?('/') ? task_matcher.resolve_path(abbreviated) : task_matcher.by_prefix(abbreviated)
      return result.resolved.item if result.resolved
      if result.ambiguous?
        return CurrentTask.choose(result.matches.map(&:item), abbreviated, kind: 'task', chooser: chooser, tty: tty)
      end
      parent, child = abbreviated.split('/', 2)
      child && 'main'.start_with?(child) ? CurrentTask.select(all_tasks.select(&:top_level?), parent, kind: 'task', chooser: chooser, tty: tty) : nil
    end

    def find_tree(abbreviated, chooser: @chooser, tty: $stdin.tty?)
      return nil if abbreviated.nil?
      if abbreviated.to_s.start_with?('/')
        raise Error, "Directory does not exist: #{abbreviated}" unless Dir.exist?(abbreviated)
        return Tree.from_path(File.realpath(abbreviated))
      end
      CurrentTask.select(all_trees, abbreviated, kind: 'tree', chooser: chooser, tty: tty)
    end

    def find_session(abbreviated, chooser: @chooser, tty: $stdin.tty?)
      return nil if abbreviated.nil?
      CurrentTask.select(all_sessions, abbreviated, kind: 'workspace', chooser: chooser, tty: tty)
    end

    def find_app(abbreviated, chooser: @chooser, tty: $stdin.tty?)
      return nil if abbreviated.nil?
      CurrentTask.select(all_apps, abbreviated, kind: 'app', chooser: chooser, tty: tty)
    end

    def external_task_tree
      directory = context.worktree_path
      Tree.from_path(directory) if directory && Dir.exist?(directory)
    end
  end
end
