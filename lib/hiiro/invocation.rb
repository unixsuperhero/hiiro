require 'sequel'
require 'securerandom'

class Hiiro
  class Invocation < Sequel::Model(:invocations)
    Hiiro::DB.register(self)
    unrestrict_primary_key

    def self.create_table!(db)
      db.create_table?(:invocations) do
        String :id, primary_key: true
        String :command
        String :pwd
        String :task
        String :worktree
        String :git_branch
        String :herdr_workspace
        String :herdr_tab
        String :herdr_pane
        String :entered_at
      end
    end

    def self.migrate!(db)
      columns = db.schema(:invocations).map(&:first)
      additions = %i[herdr_workspace herdr_tab herdr_pane] - columns
      return if additions.empty?

      db.alter_table(:invocations) do
        additions.each { |column| add_column column, String }
      end
    end

    one_to_many :resolutions,
      class: 'Hiiro::InvocationResolution',
      key: :invocation_id,
      order: :depth

    # Record this process's context. Creates a new Invocation if none exists
    # (no HIIRO_INVOCATION_ID env var), or appends a resolution if one does.
    # Returns the invocation.
    def self.record!(bin:, subcmd: nil, args: [])
      invocation_id = ENV['HIIRO_INVOCATION_ID']

      if invocation_id
        inv = where(id: invocation_id).first
        if inv
          depth = InvocationResolution.where(invocation_id: invocation_id).count
          InvocationResolution.create(
            invocation_id: invocation_id,
            depth: depth,
            bin: bin,
            subcmd: subcmd,
            args_json: Hiiro::DB::JSON.dump(Array(args)),
            created_at: Time.now.iso8601
          )
        end
        inv
      else
        id = "inv_#{Time.now.strftime('%Y%m%d%H%M%S%L')}_#{SecureRandom.hex(4)}"
        ENV['HIIRO_INVOCATION_ID'] = id

        command = ([bin] + Array(args)).join(' ')
        inv = create(
          id: id,
          command: command,
          pwd: Dir.pwd,
          task: ENV['HIIRO_TASK'],
          worktree: detect_worktree,
          git_branch: detect_git_branch,
          herdr_workspace: ENV['HERDR_WORKSPACE_ID'],
          herdr_tab: ENV['HERDR_TAB_ID'],
          herdr_pane: ENV['HERDR_PANE_ID'],
          entered_at: Time.now.iso8601
        )

        InvocationResolution.create(
          invocation_id: id,
          depth: 0,
          bin: bin,
          subcmd: subcmd,
          args_json: Hiiro::DB::JSON.dump(Array(args)),
          created_at: Time.now.iso8601
        )

        inv
      end
    rescue => e
      warn "Invocation tracking error: #{e}" if ENV['HIIRO_DEBUG']
      nil
    end

    private

    def self.detect_git_branch
      `git rev-parse --abbrev-ref HEAD 2>/dev/null`.chomp.then { |b| b.empty? ? nil : b }
    rescue
      nil
    end

    def self.detect_worktree
      `git rev-parse --show-toplevel 2>/dev/null`.chomp.then { |w| w.empty? ? nil : w }
    rescue
      nil
    end

  end

  class InvocationResolution < Sequel::Model(:invocation_resolutions)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:invocation_resolutions) do
        primary_key :id
        String :invocation_id, null: false
        Integer :depth, default: 0
        String :bin
        String :subcmd
        String :args_json
        String :created_at
      end
    end

    many_to_one :invocation, class: 'Hiiro::Invocation', key: :invocation_id

    def args = Hiiro::DB::JSON.load(args_json) || []
  end
end
