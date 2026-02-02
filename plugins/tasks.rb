require 'yaml'
require 'fileutils'
require 'open3'

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
  attr_reader :name, :parent_name, :tree_name, :session_name

  def initialize(name:, parent_task: nil, tree: nil, session: nil)
    @name = name
    @parent_name = parent_task
    @tree_name = tree
    @session_name = session || name
  end

  def subtask?
    !parent_name.nil?
  end

  def top_level?
    !subtask?
  end

  def full_name
    if subtask?
      "#{parent_name}/#{name}"
    else
      name
    end
  end

  def ==(other)
    other.is_a?(Task) && name == other.name
  end

  def to_s
    name
  end

  def to_h
    h = { 'name' => name }
    h['parent_task'] = parent_name if parent_name
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
    @config ||= Tasks::Config.new
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
end

class Tasks
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

    def apps_hash
      return {} unless File.exist?(apps_file)
      YAML.safe_load_file(apps_file) || {}
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
      return { 'tasks' => [] } unless File.exist?(tasks_file)
      YAML.safe_load_file(tasks_file) || { 'tasks' => [] }
    end

    def save_tasks(data)
      FileUtils.mkdir_p(File.dirname(tasks_file))
      File.write(tasks_file, YAML.dump(data))
    end
  end
end
