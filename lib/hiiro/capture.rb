require 'sequel'

class Hiiro
  class Capture < Sequel::Model(:captures)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:captures) do
        primary_key :id
        String :name, null: false
        String :path, null: false
        String :command
        Integer :exit_status
      end
    end

    # Most-recent-first scope. id is autoincrement, so desc(:id) == chronological reverse.
    def self.recent(limit = nil)
      ds = order(Sequel.desc(:id))
      limit ? ds.limit(limit).all : ds.all
    end

    # Fetch the capture at offset n from the most recent (0 = newest).
    def self.at_offset(n)
      order(Sequel.desc(:id)).offset(n.to_i).first
    end

    def status_glyph
      case exit_status
      when 0   then "\e[32m✓\e[0m"
      when nil then "\e[33m?\e[0m"
      else          "\e[31m✗\e[0m"
      end
    end

    def display_string(idx)
      cmd = command.to_s
      cmd = cmd[0, 57] + '…' if cmd.length > 60
      format("%4d. %s  %-22s  %s", idx, status_glyph, name, cmd)
    end
  end
end
