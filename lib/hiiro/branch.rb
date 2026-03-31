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
        String :tmux_json   # JSON: { session, window, pane }
        String :sha
        String :note
        String :created_at
        String :updated_at
      end
    end

    def tmux     = Hiiro::DB::JSON.load(tmux_json) || {}
    def tmux=(v) ; self.tmux_json = Hiiro::DB::JSON.dump(v); end

    def self.for_task(task_name)    = where(task: task_name).all
    def self.for_worktree(wt)       = where(worktree: wt).all
    def self.find_by_name(n)        = where(name: n).first
    def self.ordered                = order(Sequel.desc(:created_at))
  end
end
