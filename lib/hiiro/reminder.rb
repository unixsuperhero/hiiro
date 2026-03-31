require 'sequel'

class Hiiro
  class Reminder < Sequel::Model(:reminders)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:reminders) do
        primary_key :id
        String :message
        String :interval
        String :sound
        TrueClass :enabled
        TrueClass :once
        String :trigger_at
        String :last_triggered
        String :created_at
      end
    end

    def self.active = where(enabled: true)
    def self.due = active.where { trigger_at <= Time.now.iso8601 }
  end
end
