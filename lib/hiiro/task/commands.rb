class Hiiro
  # Builds the Hiiro command interface for task operations.
  # Inherits from BaseCommands for consistent command registration.
  class TaskCommands < BaseCommands
    protected

    def command_prefix
      nil # Task uses parent's args directly
    end

    def register_commands(h)
      tm = manager
      parent = parent_hiiro

      # List commands
      h.add_subcmd(:list) { tm.list }
      h.add_subcmd(:ls) { tm.list }

      # Task lifecycle
      h.add_subcmd(:start) { |task_name, app_name = nil| tm.start_task(task_name, app_name: app_name) }
      h.add_subcmd(:switch) { |task_name = nil, app_name = nil| TaskActions.switch(tm, h, task_name, app_name) }
      h.add_subcmd(:stop) { |task_name = nil| TaskActions.stop(tm, h, task_name) }

      # App commands
      h.add_subcmd(:app) { |app_name = nil| TaskActions.app(tm, h, app_name) }
      h.add_subcmd(:apps) { tm.list_apps }
      h.add_subcmd(:cd) { |app_name = nil| tm.cd_to_app(app_name) }
      h.add_subcmd(:path) { |app_name = nil| tm.print_app_path(app_name) }

      # Value selectors
      h.add_subcmd(:branch) { |task_name = nil| print tm.value_for_task(task_name) { |t| t.branch(tm.environment) } }
      h.add_subcmd(:tree) { |task_name = nil| print tm.value_for_task(task_name, &:tree_name) }
      h.add_subcmd(:session) { |task_name = nil| print tm.value_for_task(task_name, &:session_name) }

      # Current task info
      h.add_subcmd(:current) { TaskActions.current(tm) }
      h.add_subcmd(:cbranch) { TaskActions.cbranch(tm) }
      h.add_subcmd(:ctree) { TaskActions.ctree(tm) }
      h.add_subcmd(:csession) { TaskActions.csession(tm) }

      # Status commands
      h.add_subcmd(:status) { tm.status }
      h.add_subcmd(:st) { tm.status }
      h.add_subcmd(:save) { tm.save }

      # Edit
      h.add_subcmd(:edit) { system(ENV['EDITOR'] || 'nvim', __FILE__) }

      # Nested subcommands
      h.add_subcmd(:todo) { |*args| TaskActions.todo(tm, parent, args) }
      h.add_subcmd(:queue) { |*args| TaskActions.queue(tm, parent, h) }
      h.add_subcmd(:service) { |*args| TaskActions.service(tm, h) }
      h.add_subcmd(:run) { |*args| TaskActions.run(parent, h) }
      h.add_subcmd(:file) { |*args| TaskActions.file(tm, h) }
    end
  end
end
