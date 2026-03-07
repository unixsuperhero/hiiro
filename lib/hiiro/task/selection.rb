class Hiiro
  # Handles interactive task selection via fuzzyfind.
  # Builds a mapping of display lines to task/session info.
  class TaskSelection
    attr_reader :manager

    def initialize(manager)
      @manager = manager
    end

    # Get the selected task/session via fuzzyfind.
    #
    # @return [Hash, nil] selection info or nil
    def selected
      return nil if mapping.empty?
      manager.hiiro.fuzzyfind_from_map(mapping)
    end

    def mapping
      @mapping ||= build_mapping
    end

    private

    def build_mapping
      mapping = {}

      task_list = manager.scope == :subtask ? manager.tasks.sort_by(&:short_name) : manager.environment.all_tasks.sort_by(&:name)

      task_list.each do |task|
        display_name = manager.scope == :subtask ? task.short_name : task.name
        line = task.display_line(scope: manager.scope, environment: manager.environment)
        mapping[line] = { type: :task, name: display_name }
      end

      if manager.scope == :task
        add_extra_sessions(mapping)
      end

      mapping
    end

    def add_extra_sessions(mapping)
      task_session_names = manager.environment.all_tasks.map(&:session_name)
      extra_sessions = manager.environment.all_sessions.reject { |s| task_session_names.include?(s.name) }

      extra_sessions.sort_by(&:name).each do |session|
        line = format("%-25s  (tmux session)", session.name)
        mapping[line] = { type: :session, name: session.name }
      end
    end
  end
end
