require 'sequel'

class Hiiro
  class PinRecord < Sequel::Model(:pins)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:pins) do
        primary_key :id
        String :command, null: false
        String :key, null: false
        String :value_json
        unique [:command, :key]
      end
    end

    # Value accessor — tries JSON parse, falls back to raw string
    def value
      Hiiro::DB::JSON.load(value_json)
    rescue
      value_json
    end

    def value=(v)
      self.value_json = v.is_a?(String) ? v : Hiiro::DB::JSON.dump(v)
    end

    def self.for_command(cmd) = where(command: cmd.to_s).all
    def self.find_key(cmd, key) = where(command: cmd.to_s, key: key.to_s).first
  end
end
