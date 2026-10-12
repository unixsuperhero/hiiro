class Hiiro
  class TaskLocation
    def self.for(task, **options) = new(task, **options)

    def self.contains?(root, path)
      return false unless root && path && Dir.exist?(root)

      real = File.realpath(root)
      candidate = File.exist?(path) ? File.realpath(path) : File.expand_path(path)
      candidate == real || candidate.start_with?(real == File::SEPARATOR ? real : real + File::SEPARATOR)
    end

    attr_reader :task, :work_dir, :override, :app, :project, :invocation_directory,
                :root_directory, :root_source, :start_directory, :source, :task_source, :terminal

    def initialize(task, work_dir: Hiiro::WORK_DIR, override: nil, app: nil, root: nil,
                   root_source: nil, project: nil, invocation_directory: Dir.pwd,
                   task_source: nil, terminal: Herdr::Location.from_env, directory_source: :override)
      @task = task
      @work_dir = work_dir
      @project = project
      @invocation_directory = existing_directory(invocation_directory)
      @task_source = task_source || (task && :explicit)
      @terminal = terminal
      if root
        @root_directory = existing_directory(root, base: @invocation_directory)
        @root_source = root_source || :override
      elsif task
        path = File.expand_path(code_directory || home)
        @root_directory = (Dir.exist?(path) ? File.realpath(path) : path).freeze
        @root_source = task.primary_directory ? :primary : (worktree_path ? :tree : :home)
      else
        git_root = IO.popen(['git', '-C', @invocation_directory, 'rev-parse', '--show-toplevel'], err: File::NULL, &:read).strip
        @root_directory = existing_directory(git_root.empty? ? @invocation_directory : git_root)
        @root_source = git_root.empty? ? :cwd : :git
      end
      @app = app.is_a?(String) ? Environment.new(path: @invocation_directory).find_app(app) : app
      raise Error, "App not found: #{app}" if app && !@app
      app_path = @app && existing_directory(@app.resolve(@root_directory))
      if app_path && !self.class.contains?(@root_directory, app_path)
        raise Error, "App #{@app.name} escapes root #{@root_directory}: #{app_path}"
      end
      @override = override && existing_directory(override, base: @invocation_directory)
      @start_directory = @override || app_path || @root_directory
      @source = @override ? directory_source : (@app ? :app : @root_source)
      freeze
    end

    def home = task && TaskRecord.home_for(task.name)

    def worktree_path
      return nil unless task&.tree
      task.tree.start_with?('/') ? task.tree : File.join(work_dir, task.tree)
    end

    def code_directory = task && (task.primary_directory || worktree_path)
    def app_directory = app && app.resolve(root_directory)
    def workspace_label = task && (task.session || task.name).tr('.', '_')
    def contains?(path) = self.class.contains?(root_directory, path)

    def for_app(selected)
      self.class.for(task, **derivation, app: selected, override: override, directory_source: source)
    end

    def with_directory(directory, source:)
      self.class.for(task, **derivation, app: app, override: directory, directory_source: source)
    end

    def validate!
      existing_directory(start_directory)
      self
    end

    private

    def derivation
      { work_dir: work_dir, root: Dir.exist?(root_directory) ? root_directory : nil, root_source: root_source, project: project,
        invocation_directory: invocation_directory, task_source: task_source, terminal: terminal }
    end

    def existing_directory(path, base: Dir.pwd)
      raise Error, 'Directory reference cannot be empty' if path.to_s.strip.empty?
      expanded = File.expand_path(path, base)
      raise Error, "Directory does not exist: #{expanded}" unless Dir.exist?(expanded)
      File.realpath(expanded).freeze
    end
  end
end
