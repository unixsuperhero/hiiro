require 'sequel'
require 'uri'

class Hiiro
  class TaskRecord < Sequel::Model(:tasks)
    Hiiro::DB.register(self)

    METADATA_COLUMNS = %i[status next_action waiting_on primary_directory updated_at completed_at archived_at].freeze
    STATUSES = %w[active waiting done archived].freeze

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


    def self.migrate!(db)
      columns = db.schema(:tasks).map(&:first)
      METADATA_COLUMNS.each do |column|
        db.alter_table(:tasks) { add_column column, String } unless columns.include?(column)
      end
    end

    def self.home_for(name)
      component = URI::DEFAULT_PARSER.escape(name.to_s, /[^A-Za-z0-9._-]/)
      component = component.gsub('.', '%2E') if %w[. ..].include?(component)
      raise ArgumentError, 'Task name cannot be empty' if component.empty?

      File.join(Dir.home, 'notes', 'work', component)
    end

    def home
      self.class.home_for(name)
    end

    def task_status
      status || 'active'
    end

    def task_attributes
      values.reject { |key, _| key == :id }.compact
    end

    def resources
      TaskResource.where(task_id: id).order(:id)
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

  class TaskResource < Sequel::Model(:task_resources)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:task_resources) do
        primary_key :id
        foreign_key :task_id, :tasks, null: false, on_delete: :cascade
        String :kind, null: false
        String :target, null: false
        String :label
        String :created_at
        unique [:task_id, :kind, :target]
      end
    end
  end
end
