require 'shellwords'

class Hiiro
  class TaskSessions
    class Error < Hiiro::Error; end

    def initialize(client, workspace:, directory:)
      @client = client
      @workspace = workspace
      @directory = directory
    end

    def run(tool, argv)
      raise Error, "Unknown AI tool: #{tool}" unless %w[omp codex claude].include?(tool)

      first = argv.first
      resume = first && !first.empty? && 'resume'.start_with?(first)
      args = resume ? argv.drop(1) : argv
      if resume && args.empty?
        panes = @client.panes(workspace: @workspace).select { |pane| pane.agent == tool }
        if panes.length > 1
          raise Error, "Multiple running #{tool} panes: #{panes.map(&:id).join(', ')}; choose a pane or pass native resume arguments"
        end
        if (pane = panes.first)
          raise Error, "Could not focus pane #{pane.id}" unless @client.focus_pane(pane.id)

          return pane.id
        end
      end

      command = [tool]
      command << (tool == 'codex' ? 'resume' : '--resume') if resume
      command.concat(args)
      created = Herdr::TabCreation.create(
        @client,
        name: tool,
        workspace: @workspace,
        start_directory: @directory,
        focus: true,
      )
      raise Error, "Could not create #{tool} tab" unless created.created?
      raise Error, "Created #{tool} tab has no root pane" unless created.complete?
      unless @client.run_in_pane(created.pane_id, Shellwords.join(command))
        raise Error, "Could not start #{tool} in pane #{created.pane_id}"
      end

      created.tab_id
    end
  end
end
