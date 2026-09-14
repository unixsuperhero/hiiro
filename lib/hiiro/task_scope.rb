class Hiiro
  class TaskScope
    class Error < Hiiro::Error; end

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
      CurrentTask.new(herdr: @herdr, pin: true).resolve!
    end
  end
end
