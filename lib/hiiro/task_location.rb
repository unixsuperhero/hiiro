class Hiiro
  # Where a task's things live: home, worktree, code directory, app directory,
  # and the directory a command should start in. Retains which input won.
  class TaskLocation
    def self.for(task, work_dir: Hiiro::WORK_DIR, override: nil, app: nil)
      new(task, work_dir: work_dir, override: override, app: app)
    end

    # Realpath containment: path is root or lives under it. False when root is missing.
    def self.contains?(root, path)
      return false unless root && Dir.exist?(root)

      real = File.realpath(root)
      path == real || path.start_with?(real == File::SEPARATOR ? real : real + File::SEPARATOR)
    end

    attr_reader :task, :work_dir, :override, :app

    def initialize(task, work_dir:, override: nil, app: nil)
      @task = task
      @work_dir = work_dir
      @override = override
      @app = app
    end

    # Task notes directory. Does not create it.
    def home = TaskRecord.home_for(task.name)

    # Assigned worktree: absolute as given, else under work_dir. nil without a tree.
    def worktree_path
      return nil unless task.tree
      task.tree.start_with?('/') ? task.tree : File.join(work_dir, task.tree)
    end

    def code_directory = task.primary_directory || worktree_path

    # app resolved under the code directory; nil unless both are known.
    def app_directory
      root = code_directory
      app && root ? app.resolve(root) : nil
    end

    def start_directory = override || app_directory || code_directory || home

    # Which input produced start_directory.
    def source
      if override        then :override
      elsif app_directory then :app
      elsif task.primary_directory then :primary
      elsif worktree_path then :tree
      else :home
      end
    end

    def contains?(path) = self.class.contains?(code_directory, path)

    def workspace_label = (task.session || task.name).tr('.', '_')
  end
end
