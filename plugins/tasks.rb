WORK_DIR = File.join(Dir.home, 'work')
REPO_PATH = File.join(WORK_DIR, '.bare')

class Environment
  def self.current
    new(
      task: Task.current,
      tree: Tree.current,
      session: TmuxSession.current,
      path: Dir.pwd,
    )
  end

  attr_reader :task, :tree, :session, :path

  def initialize(task:, tree:, session:, path: Dir.pwd)
    @task = task
    @tree = tree
    @session = session
    @path = path
  end
end

def TmuxSession
  def self.current
    session_name = `tmux display-message -p '#S'`.chomp

    new(session_name)
  end

  def self.all
    all_sessions = `tmux list-sessions -F '#S'`.lines(chomp: true)

    all_sessions.map { |name| new(name) }
  end

  attr_reader :name

  def initialize(name)
    @name = name
  end
end

class Tree
  def self.current
    all.find(&:match?)
  end

  def self.all(repo_path: REPO_PATH)
    output = `git -C #{repo_path} worktree list --porcelain 2>/dev/null`

    trees = []
    current_tree = nil

    output.lines(chomp: true).each do |line|
      case line
      in /^worktree (.*)/
        unless current_tree.nil?
          trees << new(**current_tree)
          current_tree = nil
        end

        current_tree ||= {}
        current_tree[:path] = $1
      in /^HEAD (.*)/
        current_tree ||= {}
        current_tree[:head] = $1
      in /^branch refs.heads.(.*)/
        current_tree ||= {}
        current_tree[:branch] = $1
      end
    end

    return trees if current_tree.nil?

    trees << current_tree
  end

  attr_reader :path, :head, :branch

  def initialize(path:, head:, branch: nil)
    @path = path
    @head = head
    @branch = branch
  end

  def match?(pwd = Dir.pwd)
    Dir.pwd.start_with?(root)
  end

  def root
    path + '/'
  end

  def detached?
    branch.nil?
  end
end

class Task
  def self.all
    loaded_tasks = YAML.safe_load_file(File.join(Dir.home, '.config/hiiro/tasks/assignments.yml'))

    loaded_tasks.map do |path, name|
      new(name, path)
    end
  end

  def self.current
    current_session = TmuxSession.current
    current_tree = Tree.current

    all.find do |task|
      task.session == current_session ||
        task.tree == current_tree
    end
  end

  def self.by_name(name, parent_name: nil)
    all.find do |task|
      task.name.start_with?(name) &&
        !task.name.sub(name, '').include?('/')
    end
  end
end

class Tasks
  attr_reader :hiiro, :scope, :environment

  def initialize(hiiro, scope: nil, environment: nil)
    @hiiro = hiiro
    @scope = scope || :task
    @environment = environment || Environment.current
  end
end
