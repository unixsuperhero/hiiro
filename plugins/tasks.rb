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
