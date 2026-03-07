class Hiiro
  # Base class for command builders that register subcommands with Hiiro.
  # Subclasses implement register_commands to add their specific subcommands.
  #
  # @example
  #   class MyCommands < Hiiro::BaseCommands
  #     def command_prefix
  #       :mycommand
  #     end
  #
  #     def register_commands(h)
  #       h.add_subcmd(:list) { MyActions.list(manager) }
  #       h.add_subcmd(:add) { |name| MyActions.add(manager, name) }
  #     end
  #   end
  #
  class BaseCommands
    attr_reader :manager, :parent_hiiro, :context

    # @param manager [Object] the domain manager (Queue, ServiceManager, TaskManager)
    # @param parent_hiiro [Hiiro] the parent Hiiro instance
    # @param context [Hash] additional context passed to subcommands
    def initialize(manager, parent_hiiro, **context)
      @manager = manager
      @parent_hiiro = parent_hiiro
      @context = context
    end

    # Build a child Hiiro instance with registered subcommands.
    #
    # @return [Hiiro] configured child Hiiro instance
    def build
      prefix = command_prefix
      parent_hiiro.make_child(prefix) do |h|
        register_commands(h)
      end
    end

    protected

    # Override to specify a command prefix for nested commands.
    # Return nil for no prefix (inherits parent's args directly).
    #
    # @return [Symbol, nil] command prefix
    def command_prefix
      nil
    end

    # Override to register subcommands on the Hiiro instance.
    #
    # @param h [Hiiro] the Hiiro instance to add commands to
    # @raise [NotImplementedError] if not overridden
    def register_commands(h)
      raise NotImplementedError, "#{self.class}#register_commands must be implemented"
    end

    # Helper to access context values.
    #
    # @param key [Symbol] context key
    # @return [Object] context value
    def get_context(key)
      context[key]
    end
  end
end
