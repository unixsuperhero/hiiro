require 'shellwords'

class Hiiro
  module Background
    WORKSPACE = 'h-bg'

    # Run cmd asynchronously. Inside Herdr, reuses an idle shell pane in the
    # h-bg workspace and only opens a new unfocused tab when every pane there is
    # busy, so the workspace never grows past the number of concurrent jobs.
    # Outside Herdr, falls back to a detached spawn.
    #
    # dir: optional directory to cd into before running the command.
    def self.run(*cmd, dir: nil, client: nil)
      if inside_herdr?
        client ||= Hiiro::Herdr.client
        workspace = ensure_workspace(client)
        command = cmd.shelljoin
        command = "cd #{dir.shellescape} && #{command}" if dir
        if (pane = idle_pane(client, workspace))
          client.run_in_pane(pane.id, command)
        else
          client.new_tab(
            name: cmd.first.to_s,
            workspace: workspace,
            start_directory: dir,
            command: command,
            focus: false
          )
        end
      else
        spawn_opts = dir ? { chdir: dir } : {}
        Process.detach(spawn(*cmd, **spawn_opts))
      end
    rescue
      nil
    end

    def self.inside_herdr?
      ENV['HERDR_ENV'] == '1'
    end

    def self.ensure_workspace(client = Hiiro::Herdr.client)
      client.find_workspace(WORKSPACE) || client.new_workspace(WORKSPACE, focus: false)
    end

    # A pane in the workspace sitting at a shell prompt with no foreground command.
    def self.idle_pane(client, workspace)
      client.panes(workspace: workspace).find { |pane| pane.agent.nil? && pane.foreground_command.nil? }
    end
  end
end
