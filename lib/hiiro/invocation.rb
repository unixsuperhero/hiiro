require 'sequel'
require 'open3'

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

    # Write the invocation `id` (from its root frame, unless it already exists)
    # and each frame not yet written, as resolutions in order. See Hiiro::Runtime.
    def self.record_frames!(id, frames)
      db.transaction do
        unless where(id: id).count.positive?
          root = frames.first
          dataset.insert_conflict.insert(
            id: id,
            command: [root['bin'], root['subcmd'], *Array(root['args'])].compact.join(' '),
            pwd: root['pwd'],
            task: ENV['HIIRO_TASK'],
            worktree: detect_worktree(root['pwd']),
            git_branch: detect_git_branch(root['pwd']),
            herdr_workspace: ENV['HERDR_WORKSPACE_ID'],
            herdr_tab: ENV['HERDR_TAB_ID'],
            herdr_pane: ENV['HERDR_PANE_ID'],
            entered_at: Time.now.iso8601
          )
        end

        frames.each do |frame|
          resolutions = InvocationResolution.where(invocation_id: id)
          next if resolutions.where(frame_id: frame['id']).count.positive?

          InvocationResolution.create(
            invocation_id: id,
            frame_id: frame['id'],
            depth: resolutions.count,
            bin: frame['bin'],
            subcmd: frame['subcmd'],
            args_json: Hiiro::DB::JSON.dump(Array(frame['args'])),
            created_at: Time.now.iso8601
          )
        end
      end
      self[id]
    rescue => e
      warn "Invocation tracking error: #{e}" if ENV['HIIRO_DEBUG']
      nil
    end

    def self.detect_git_branch(dir)
      git_line(dir, 'rev-parse', '--abbrev-ref', 'HEAD')
    end

    def self.detect_worktree(dir)
      git_line(dir, 'rev-parse', '--show-toplevel')
    end

    def self.git_line(dir, *args)
      return nil unless dir && Dir.exist?(dir)

      out, status = Open3.capture2('git', '-C', dir, *args, err: File::NULL)
      line = out.chomp
      status.success? && !line.empty? ? line : nil
    rescue SystemCallError
      nil
    end
  end

  class InvocationResolution < Sequel::Model(:invocation_resolutions)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:invocation_resolutions) do
        primary_key :id
        String :invocation_id, null: false
        String :frame_id
        Integer :depth, default: 0
        String :bin
        String :subcmd
        String :args_json
        String :created_at
      end
    end

    def self.migrate!(db)
      return if db.schema(:invocation_resolutions).map(&:first).include?(:frame_id)

      db.alter_table(:invocation_resolutions) { add_column :frame_id, String }
    end

    many_to_one :invocation, class: 'Hiiro::Invocation', key: :invocation_id

    def args = Hiiro::DB::JSON.load(args_json) || []
  end
end
