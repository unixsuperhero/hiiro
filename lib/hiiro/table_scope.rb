class Hiiro
  # Which entries of a table are visible: every entry (global) or only those
  # attached to one task. A global scope may still remember a task so toggling
  # back to task scope does not re-resolve it.
  class TableScope
    attr_reader :mode, :task

    def self.global(task = nil) = new(:global, task)

    def self.task(record)
      raise ArgumentError, 'task scope needs a task' if record.nil?

      new(:task, record)
    end

    def self.current(cwd: Dir.pwd, resolver: nil)
      record = resolve(cwd:, resolver:)
      record ? task(record) : global
    end

    def self.resolve(cwd: Dir.pwd, resolver: nil)
      return resolver.call if resolver

      CurrentTask.new(herdr: -> { Hiiro::Herdr.client }, cwd:, pin: false).resolve
    end

    def initialize(mode, task)
      @mode = mode
      @task = task
      freeze
    end

    def global? = mode == :global
    def task?   = mode == :task

    def label = task? ? "task(@#{task.name})" : 'global'

    def toggle(resolver: nil)
      return self.class.global(task) if task?

      record = task || self.class.resolve(resolver:)
      record ? self.class.task(record) : self
    end

    def apply(dataset) = task? ? dataset.where(task_id: task.id) : dataset

    def ==(other) = other.is_a?(TableScope) && mode == other.mode && task&.id == other.task&.id
    alias eql? ==
    def hash = [mode, task&.id].hash
  end
end
