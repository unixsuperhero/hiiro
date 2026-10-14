class Hiiro
  class CurrentTask
    def self.select(items, reference, kind:, key: :name, chooser: nil, tty: $stdin.tty?)
      raise Error, "#{kind.capitalize} reference cannot be empty" if reference.to_s.strip.empty?
      result = Matcher.new(items, key).by_prefix(reference.to_s)
      candidates = result.matches.map(&:item)
      exact = candidates.select { |item| item.public_send(key) == reference.to_s }
      candidates = exact unless exact.empty?
      return candidates.first if candidates.one?
      return nil if candidates.empty?
      choose(candidates, reference, kind: kind, key: key, chooser: chooser, tty: tty)
    end

    def self.choose(candidates, reference, kind:, key: :name, chooser: nil, tty: $stdin.tty?)
      raise Error, "Ambiguous #{kind} #{reference}: #{candidates.map { |item| item.public_send(key) }.join(', ')}" unless tty && chooser
      labels = candidates.map { |item| item.public_send(key) }
      counts = labels.tally
      mapping = candidates.each_with_index.to_h do |item, index|
        label = labels[index]
        [counts[label] > 1 ? "#{label} [#{index + 1}]" : label, item]
      end
      chosen = chooser.call(mapping)
      raise Error, "No #{kind} selected" unless candidates.include?(chosen)
      chosen
    end

    attr_reader :task_source, :terminal

    def initialize(herdr: nil, cwd: Dir.pwd, pin: true, tasks: nil, task: nil, env: ENV, chooser: nil)
      @herdr = herdr
      @cwd = cwd
      @pin = pin
      @tasks = tasks
      @explicit = task
      @herdr_env = env['HERDR_ENV'] == '1'
      @chooser = chooser
      @terminal = Herdr::Location.from_env(env)
    end

    def resolve
      return @resolved if defined?(@resolved)
      @resolved = if @explicit
        @task_source = :explicit
        @explicit.is_a?(TaskRecord) ? @explicit : self.class.select(tasks, @explicit, kind: 'task', chooser: @chooser) || raise(Error, "Task not found: #{@explicit}")
      else
        select_inferred
      end
    end

    def resolve!
      resolve || raise(Error, 'No current task; supply a task name or run t use NAME')
    end

    def context(app: nil, root: nil, root_source: nil, project: nil, override: nil)
      task = resolve
      TaskLocation.for(task, app: app, root: root, root_source: root_source, project: project,
                       override: override, invocation_directory: @cwd, task_source: task_source, terminal: terminal)
    end

    private

    def tasks = @tasks ||= TaskRecord.all_as_list

    def select_inferred
      [[:workspace, -> { herdr_task }], [:directory, -> { directory_task }], [:pin, -> { pinned_task }]].each do |source, resolver|
        task = resolver.call
        next unless task
        @task_source = source
        return task
      end
      nil
    end

    def herdr_task
      if @herdr_env && !terminal.target
        raise Error, 'Missing calling Herdr workspace/pane IDs; supply a task name'
      end
      return nil unless terminal.target
      adapter = @herdr || Herdr.client
      client = adapter.respond_to?(:call) ? adapter.call : adapter
      @terminal = terminal.validate!(client)
      workspace = client.get_workspace(terminal.workspace_id)
      matches = tasks.select { |task| TaskLocation.for(task).workspace_label == workspace.name }
      raise Error, "Ambiguous workspace task: #{matches.map(&:name).join(', ')}" if matches.length > 1
      matches.first
    end

    def directory_task
      raise Error, "Directory does not exist: #{@cwd}" unless Dir.exist?(@cwd)
      cwd = File.realpath(@cwd)
      registered = TaskResource.where(kind: 'directory').select_map([:task_id, :target]).group_by(&:first)
      matches = tasks.select do |task|
        location = TaskLocation.for(task)
        paths = [location.home, location.code_directory, *registered.fetch(task.id, []).map(&:last)].compact
        paths.any? { |path| TaskLocation.contains?(path, cwd) }
      end
      raise Error, "Ambiguous directory task: #{matches.map(&:name).join(', ')}" if matches.length > 1
      matches.first
    end

    def pinned_task
      return nil unless @pin
      saved = Table.named('t').find('current_task')
      return nil unless saved
      TaskRecord[saved.value.to_i] || raise(Error, 'Saved task no longer exists; run t use NAME')
    end
  end
end
