class Hiiro
  class ServiceManager
    # Builds the Hiiro command interface for service operations.
    # Inherits from BaseCommands for consistent command registration.
    class Commands < BaseCommands
      protected

      def command_prefix
        :service
      end

      def register_commands(h)
        sm = manager
        tm = get_context(:task_manager)

        # List commands
        h.add_subcmd(:ls) { Actions.list(sm, tm) }
        h.add_subcmd(:list) { Actions.list(sm, tm) }

        # Lifecycle commands
        h.add_subcmd(:start) { |svc_name = nil, *extra| Actions.start(sm, h, svc_name, extra, tm) }
        h.add_subcmd(:stop) { |svc_name = nil| Actions.stop(sm, h, svc_name) }
        h.add_subcmd(:reset) { |svc_name = nil| Actions.reset(sm, h, svc_name) }
        h.add_subcmd(:clean) { sm.clean }

        # Navigation
        h.add_subcmd(:attach) { |svc_name = nil| Actions.attach(sm, h, svc_name) }

        # URL/Port
        h.add_subcmd(:open) { |svc_name = nil| Actions.open(sm, svc_name) }
        h.add_subcmd(:url) { |svc_name = nil| Actions.url(sm, svc_name) }
        h.add_subcmd(:port) { |svc_name = nil| Actions.port(sm, svc_name) }

        # Status
        h.add_subcmd(:status) { |svc_name = nil| Actions.status(sm, h, svc_name) }

        # Config management
        h.add_subcmd(:add) { Actions.add(sm) }
        h.add_subcmd(:rm) { |svc_name = nil| Actions.remove(sm, svc_name) }
        h.add_subcmd(:remove) { |svc_name = nil| Actions.remove(sm, svc_name) }
        h.add_subcmd(:config) { Actions.config(sm) }

        # Group commands
        h.add_subcmd(:groups) { Actions.groups(sm) }

        # Env commands
        h.add_subcmd(:env) { |svc_name = nil| Actions.env(sm, svc_name) }
      end
    end
  end
end
