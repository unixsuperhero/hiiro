require 'sequel'

class Hiiro
  class TaskRecord < Sequel::Model(:tasks)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:tasks) do
        primary_key :id
        String :name, null: false
        String :tree
        String :session
        String :app
        Integer :color_index
        String :created_at
        unique :name
      end
    end

    def self.top_level
      where(Sequel.~(Sequel.like(:name, '%/%')))
    end

    def self.subtasks_of(parent_name)
      where(Sequel.like(:name, "#{parent_name}/%"))
        .exclude(Sequel.like(:name, "#{parent_name}/%/%"))
    end

    def self.find_by_name(n)
      where(name: n).first
    end

    def self.all_as_list
      order(:name).all
    end
  end
end
