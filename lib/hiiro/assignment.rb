require 'sequel'

class Hiiro
  class Assignment < Sequel::Model(:assignments)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:assignments) do
        primary_key :id
        String :worktree, null: false
        String :branch, null: false
      end
    end

    def self.for_worktree(wt) = where(worktree: wt).first
    def self.all_as_hash = all.each_with_object({}) { |a, h| h[a.worktree] = a.branch }
  end
end
