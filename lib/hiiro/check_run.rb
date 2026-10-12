require 'sequel'

class Hiiro
  class CheckRun < Sequel::Model(:check_runs)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:check_runs) do
        primary_key :id
        Integer :pr_id
        Integer :pr_number, null: false
        String :name
        String :url
        String :status      # COMPLETED, IN_PROGRESS, QUEUED, WAITING, PENDING
        String :conclusion  # SUCCESS, FAILURE, CANCELLED, SKIPPED, NEUTRAL, TIMED_OUT
        String :updated_at
        index :pr_number
        index :pr_id
      end
    end

    def self.migrate!(db)
      return if db.schema(:check_runs).any? { |column, _| column == :pr_id }
      db.transaction(mode: :immediate) do
        db.alter_table(:check_runs) { add_column :pr_id, Integer; add_index :pr_id }
        # Legacy number-only checks stay unowned; raw per-PR caches establish ownership.
        if db.table_exists?(:prs) && db.schema(:prs).any? { |column, _| column == :check_runs_json }
          db[:prs].exclude(check_runs_json: nil).each do |pr|
            runs = Hiiro::DB::JSON.load(pr[:check_runs_json])
            Array(runs).each do |run|
              next unless run.is_a?(Hash)
              db[:check_runs].insert(Hiiro::CheckContext.from_node(run).to_row(pr_number: pr[:number]).merge(pr_id: pr[:id]))
            end
          end
        end
      end
    end

    def self.for_pr(pr_id) = where(pr_id: pr_id).all
    def self.upsert_for_pr(pr_id, runs)
      db.transaction(mode: :immediate) do
        pr = db[:prs].where(id: pr_id).first
        next unless pr
        where(pr_id: pr_id).delete
        Array(runs).each do |run|
          next unless run.is_a?(Hash)
          insert(Hiiro::CheckContext.from_node(run).to_row(pr_number: pr[:number]).merge(pr_id: pr_id))
        end
      end
    end
  end
end
