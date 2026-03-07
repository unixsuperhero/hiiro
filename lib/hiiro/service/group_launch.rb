class Hiiro
  class ServiceManager
    # Orchestrates launching a service group in tmux.
    # Creates a shared window with split panes for each service.
    class GroupLaunch
      include TmuxIntegration

      attr_reader :manager, :group, :tmux_info, :task_info

      def initialize(manager, group, tmux_info: {}, task_info: {})
        @manager = manager
        @group = group
        @tmux_info = tmux_info
        @task_info = task_info
      end

      # Execute the group launch process.
      #
      # @return [Boolean] true if launched successfully
      def call
        session = tmux_info[:session] || manager.current_tmux_session
        unless session
          puts "tmux is required to start a service group"
          return false
        end

        puts "Starting group '#{group.name}'..."

        window_target, first_pane_id = manager.create_tmux_window(session, group.name)
        last_pane_id = first_pane_id

        group.members.each_with_index do |member, idx|
          svc = manager.find_service(member.name)
          next unless svc

          if idx == 0
            pane_id = first_pane_id
          else
            pane_id = manager.split_tmux_pane(window_target, last_pane_id)
            last_pane_id = pane_id
          end

          member_tmux_info = tmux_info.merge(
            session: session,
            window: window_target,
            pane: pane_id,
          )

          manager.start(member.name,
            tmux_info: member_tmux_info,
            task_info: task_info,
            variation_overrides: member.use_overrides,
            skip_window_creation: true
          )
        end
        true
      end

    end
  end
end
