class Hiiro
  class ServiceManager
    # Value object for a service group definition.
    # A group allows starting multiple related services together.
    class Group
      attr_reader :name, :services_config

      def initialize(name:, services: [], **)
        @name = name
        @services_config = services || []
      end

      # Get group members as Member objects.
      #
      # @return [Array<Member>] array of group members
      def members
        @members ||= services_config.map do |m|
          member_name = m['name'] || m[:name]
          use_overrides = m['use'] || m[:use] || {}
          Member.new(name: member_name, use_overrides: use_overrides)
        end
      end

      # --- Actor Methods ---

      # Launch all services in this group.
      #
      # @param manager [ServiceManager] the service manager
      # @param tmux_info [Hash] tmux session/window info
      # @param task_info [Hash] current task context
      # @return [Boolean] true if launched successfully
      def launch(manager:, tmux_info: {}, task_info: {})
        GroupLaunch.new(manager, self, tmux_info: tmux_info, task_info: task_info).call
      end

      # Stop all services in this group.
      #
      # @param manager [ServiceManager] the service manager
      # @return [Boolean] true if stopped successfully
      def stop(manager:)
        members.each { |m| manager.stop(m.name) }
        true
      end
    end
  end
end
