require 'sequel'

class Hiiro
  class Branch < Sequel::Model(:branches)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:branches) do
        primary_key :id
        String :name, null: false
        String :worktree
        String :task
        String :herdr_json  # JSON: { workspace, tab, pane }
        String :tmux_json   # Legacy data retained for migration.
        String :sha
        String :note
        String :created_at
        String :updated_at
      end
    end

    def self.migrate!(db)
      columns = db.schema(:branches).map(&:first)
      return if columns.include?(:herdr_json)

      db.alter_table(:branches) { add_column :herdr_json, String }
    end

    def herdr
      current = Hiiro::DB::JSON.load(herdr_json) || {}
      return current unless current.empty?

      legacy = Hiiro::DB::JSON.load(tmux_json) || {}
      {
        'workspace' => legacy['session'],
        'tab' => legacy['window'],
        'pane' => legacy['pane'],
      }.compact
    end

    def herdr=(value)
      self.herdr_json = Hiiro::DB::JSON.dump(value)
    end

    def self.for_task(task_name)    = where(task: task_name).all
    def self.for_worktree(wt)       = where(worktree: wt).all
    def self.find_by_name(n)        = where(name: n).first
    def self.ordered                = order(Sequel.asc(:created_at))
  end
end
