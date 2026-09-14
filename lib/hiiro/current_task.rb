class Hiiro
  # Resolves the current task record shared by `t` (via TaskScope) and
  # Environment#task (via `h` commands):
  #
  #   1. Herdr workspace, when HERDR_* env vars identify one
  #   2. Working directory inside a task home, code directory, or registered directory
  #   3. Saved `t TASK current` pin (only when pin: true)
  #
  # resolve! raises Hiiro::Error with a user-facing message; resolve returns nil instead.
  class CurrentTask
    def initialize(herdr: nil, cwd: Dir.pwd, pin: true, tasks: nil)
      @herdr = herdr
      @cwd = cwd
      @pin = pin
      @tasks = tasks
    end

    def resolve
      resolve!
    rescue Hiiro::Error
      nil
    end

    def resolve!
      herdr_task || directory_task || pinned_task
    end

    private

    def tasks
      @tasks ||= TaskRecord.all_as_list
    end

    def herdr_task
      return nil unless @herdr && (ENV['HERDR_WORKSPACE_ID'] || ENV['HERDR_PANE_ID'] || ENV['HERDR_ENV'] == '1')

      herdr = @herdr.call
      unless herdr.server_running?
        raise Error, 'Herdr is not running; start Herdr for workspace/tab/pane commands, or supply a task name for task data'
      end
      pane = herdr.get_pane(ENV['HERDR_PANE_ID']) if ENV['HERDR_PANE_ID']
      raise Error, 'Cannot resolve the current Herdr pane; supply a task name' if ENV['HERDR_PANE_ID'] && !pane

      workspace_id = ENV['HERDR_WORKSPACE_ID'] || pane&.workspace_id
      raise Error, 'Conflicting Herdr pane/workspace context; supply a task name' if pane && workspace_id != pane.workspace_id

      workspace = workspace_id ? herdr.get_workspace(workspace_id) : herdr.current_workspace
      raise Error, 'Cannot resolve the current Herdr workspace; supply a task name' unless workspace

      matches = tasks.select { |task| workspace_label(task) == workspace.name }
      raise Error, "Ambiguous workspace task: #{matches.map(&:name).join(', ')}" if matches.length > 1

      matches.first
    end

    def directory_task
      cwd = File.realpath(@cwd)
      registered = TaskResource.where(kind: 'directory').select_map([:task_id, :target]).group_by(&:first)
      matches = tasks.select do |task|
        paths = [task.home, code_directory(task), *registered.fetch(task.id, []).map(&:last)].compact
        paths.any? { |path| inside?(cwd, path) }
      end
      raise Error, "Ambiguous directory task: #{matches.map(&:name).join(', ')}" if matches.length > 1

      matches.first
    end

    def pinned_task
      raise Error, 'No current task; supply a task name or run t TASK current' unless @pin

      saved = PinRecord.find_key('t', 'current_task')
      raise Error, 'No current task; supply a task name or run t TASK current' unless saved

      TaskRecord[saved.value] || raise(Error, 'Saved task no longer exists; run t TASK current')
    end

    def workspace_label(task)
      (task.session || task.name).tr('.', '_')
    end

    def code_directory(task)
      task.primary_directory || (task.tree && (task.tree.start_with?('/') ? task.tree : File.join(Hiiro::WORK_DIR, task.tree)))
    end

    def inside?(path, directory)
      return false unless Dir.exist?(directory)

      root = File.realpath(directory)
      path == root || path.start_with?(root == File::SEPARATOR ? root : root + File::SEPARATOR)
    end
  end
end
