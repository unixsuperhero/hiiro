class Hiiro
  module Background
    WORKSPACE = 'h-bg'

    # Run cmd asynchronously. Inside Herdr, spins up an unfocused tab in the
    # h-bg workspace so you can inspect it later. Outside Herdr,
    # falls back to a detached spawn.
    #
    # dir: optional directory to cd into before running the command.
    def self.run(*cmd, dir: nil)
      if inside_herdr?
        client = Hiiro::Herdr.client
        workspace = ensure_workspace(client)
        client.new_tab(
          name: cmd.first.to_s,
          workspace: workspace,
          start_directory: dir,
          command: cmd.shelljoin,
          focus: false
        )
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
  end
end
