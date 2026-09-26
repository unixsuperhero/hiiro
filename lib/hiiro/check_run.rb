require 'sequel'

class Hiiro
  class CheckRun < Sequel::Model(:check_runs)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:check_runs) do
        primary_key :id
        Integer :pr_number, null: false
        String :name
        String :url
        String :status      # COMPLETED, IN_PROGRESS, QUEUED, WAITING, PENDING
        String :conclusion  # SUCCESS, FAILURE, CANCELLED, SKIPPED, NEUTRAL, TIMED_OUT
        String :updated_at
        index :pr_number
      end
    end

    def self.for_pr(number) = where(pr_number: number.to_i).all
    def self.upsert_for_pr(number, runs)
      where(pr_number: number.to_i).delete
      Array(runs).each do |run|
        next unless run.is_a?(Hash)
        insert(Hiiro::CheckContext.from_node(run).to_row(pr_number: number.to_i))
      end
    end
  end
end
