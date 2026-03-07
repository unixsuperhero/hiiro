class Hiiro
  class Queue
    # Builds the Hiiro command interface for queue operations.
    # Inherits from BaseCommands for consistent command registration.
    class Commands < BaseCommands
      protected

      def command_prefix
        nil # Queue uses parent's args directly
      end

      def register_commands(h)
        q = manager
        ti = get_context(:task_info)

        # Watch and run commands
        h.add_subcmd(:watch) { Actions.watch(q) }
        h.add_subcmd(:run) { |name = nil| Actions.run(q, name) }

        # List commands
        h.add_subcmd(:ls) { Actions.list(q) }
        h.add_subcmd(:list) { Actions.list(q) }
        h.add_subcmd(:status) { Actions.status(q) }

        # Navigation
        h.add_subcmd(:attach) { |name = nil| Actions.attach(q, h, name) }
        h.add_subcmd(:session) { Actions.session(q) }

        # Task creation
        h.add_subcmd(:add) { |*args| Actions.add(q, h, args, ti) }
        h.add_subcmd(:wip) { |*args| Actions.wip(q, h, args, ti) }
        h.add_subcmd(:ready) { |name = nil| Actions.ready(q, h, name) }

        # Task management
        h.add_subcmd(:kill) { |name = nil| Actions.kill(q, h, name) }
        h.add_subcmd(:retry) { |name = nil| Actions.retry_task(q, h, name) }
        h.add_subcmd(:clean) { Actions.clean(q) }
        h.add_subcmd(:dir) { Actions.dir(q) }
      end
    end
  end
end
