require 'sequel'

class Hiiro
  class TrackedPr < Sequel::Model(:prs)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:prs) do
        primary_key :id
        Integer :number
        String :title
        String :url
        String :branch
        String :state
        String :worktree
        String :task
        String :tmux_json  # JSON: { session, window, pane }
        String :created_at
      end
    end

    def tmux     = Hiiro::DB::JSON.load(tmux_json) || {}
    def tmux=(v) ; self.tmux_json = Hiiro::DB::JSON.dump(v); end

    def self.for_task(t)       = where(task: t).all
    def self.for_worktree(w)   = where(worktree: w).all
    def self.open              = where(state: 'OPEN').all
    def self.find_by_number(n) = where(number: n).first
  end
end
