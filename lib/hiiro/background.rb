require 'shellwords'
require_relative 'owned_run'
require_relative 'pane_reservations'

class Hiiro
  module Background
    WORKSPACE = 'h-bg'

    # Run cmd asynchronously as an owned run. Inside Herdr, reserves an idle
    # shell pane in the h-bg workspace and only opens a new unfocused tab when
    # every pane there is busy or reserved, so the workspace never grows past
    # the number of concurrent jobs. Outside Herdr, spawns a detached supervisor.
    # Returns the started run; raises OwnedRun::LaunchError when it did not start.
    #
    # dir: optional directory to run the command in.
    def self.run(*cmd, dir: nil, client: nil, launcher: nil, reservations: PaneReservations.default)
      request = OwnedRun::LaunchRequest.new(
        owner: { kind: 'background' },
        command: CommandSpecification.new(*cmd, cwd: dir),
      )
      if inside_herdr?
        client ||= Hiiro::Herdr.client
        launcher ||= OwnedRun::Launcher.new(herdr: client)
        run_in_herdr(request, client, launcher, reservations, label: cmd.first.to_s)
      else
        launcher ||= OwnedRun::Launcher.new
        request.placement = { 'kind' => 'detached' }
        launcher.detached(request)
      end
    end

    def self.run_in_herdr(request, client, launcher, reservations, label:)
      workspace = ensure_workspace(client)
      raise Hiiro::Error, "Herdr did not create the #{WORKSPACE} workspace" unless workspace

      location = reservations.synchronize do |held|
        pane = idle_panes(client, workspace).find { |candidate| !held.reserved?(candidate.id, store: launcher.store) }
        pane ||= new_pane(client, workspace, label)
        held.reserve(pane.id, request.id)
        Herdr::Location.new(workspace_id: workspace.id, tab_id: pane.tab_id, pane_id: pane.id)
      end
      request.placement = { 'kind' => 'herdr-pane', 'pane' => location.pane_id, 'reservations' => reservations.dir }
      launcher.herdr_pane(request, location)
    rescue OwnedRun::LaunchError
      raise
    rescue Exception
      reservations.release(location.pane_id, request.id) if location
      raise
    end

    def self.inside_herdr?
      ENV['HERDR_ENV'] == '1'
    end

    def self.ensure_workspace(client = Hiiro::Herdr.client)
      client.find_workspace(WORKSPACE) || client.new_workspace(WORKSPACE, focus: false)
    end

    # Panes in the workspace sitting at a shell prompt with no foreground command.
    def self.idle_panes(client, workspace)
      client.panes(workspace: workspace).select { |pane| pane.agent.nil? && pane.foreground_command.nil? }
    end

    def self.new_pane(client, workspace, label)
      created = Herdr::TabCreation.create(client, name: label, workspace: workspace, focus: false)
      raise Hiiro::Error, "Herdr did not create a #{WORKSPACE} tab (#{created.errors.join(', ')})" unless created.complete?

      created.root_pane
    end
  end
end
