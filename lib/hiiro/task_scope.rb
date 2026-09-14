class Hiiro
  class TaskScope
    class Error < StandardError; end

    attr_reader :reference

    def initialize(reference, herdr:)
      @reference = reference.to_s
      raise Error, 'Task reference cannot be empty' if @reference.empty?

      @herdr = herdr
    end

    def explicit?
      !%w[. -].include?(reference)
    end

    def orphan?
      reference == '-'
    end

    def task
      return @task if defined?(@task)

      @task = if orphan?
        nil
      elsif explicit?
        result = Matcher.new(TaskRecord.all_as_list, :name).by_prefix(reference)
        match = result.resolved
        if !match && result.ambiguous?
          raise Error, "Ambiguous task #{reference}: #{result.matches.map { |item| item.item.name }.join(', ')}"
        end
        match&.item
      else
        current_task
      end
    end

    def task!
      raise Error, "Use t - todo for orphan todos; '-' does not select a task" if orphan?

      task || raise(Error, "Task not found: #{reference}")
    end

    private

    def current_task
      tasks = TaskRecord.all_as_list
      if ENV['HERDR_WORKSPACE_ID'] || ENV['HERDR_PANE_ID'] || ENV['HERDR_ENV'] == '1'
        herdr = @herdr.call
        unless herdr.server_running?
          raise Error, 'Herdr is not running; start Herdr for workspace/tab/pane commands, or supply a task name for task data'
        end
        pane = herdr.get_pane(ENV['HERDR_PANE_ID']) if ENV['HERDR_PANE_ID']
        if ENV['HERDR_PANE_ID'] && !pane
          raise Error, 'Cannot resolve the current Herdr pane; supply a task name'
        end
        workspace_id = ENV['HERDR_WORKSPACE_ID'] || pane&.workspace_id
        if pane && workspace_id != pane.workspace_id
          raise Error, 'Conflicting Herdr pane/workspace context; supply a task name'
        end
        workspace = workspace_id ? herdr.get_workspace(workspace_id) : herdr.current_workspace
        raise Error, 'Cannot resolve the current Herdr workspace; supply a task name' unless workspace

        matches = tasks.select { |task| (task.session || task.name).tr('.', '_') == workspace.name }
        raise Error, "Ambiguous workspace task: #{matches.map(&:name).join(', ')}" if matches.length > 1
        return matches.first if matches.one?
      end

      cwd = File.realpath(Dir.pwd)
      matches = tasks.select do |task|
        directory = task.primary_directory || (task.tree && (task.tree.start_with?('/') ? task.tree : File.join(Hiiro::WORK_DIR, task.tree)))
        paths = [task.home, directory, *task.resources.where(kind: 'directory').select_map(:target)].compact
        paths.any? { |path| inside?(cwd, path) }
      end
      raise Error, "Ambiguous directory task: #{matches.map(&:name).join(', ')}" if matches.length > 1
      return matches.first if matches.one?

      saved = PinRecord.find_key('t', 'current_task')
      raise Error, 'No current task; supply a task name or run t TASK current' unless saved

      TaskRecord[saved.value] || raise(Error, 'Saved task no longer exists; run t TASK current')
    end

    def inside?(path, directory)
      return false unless Dir.exist?(directory)

      root = File.realpath(directory)
      path == root || path.start_with?(root == File::SEPARATOR ? root : root + File::SEPARATOR)
    end
  end
end
