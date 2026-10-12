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
        String :value_format, null: false, default: 'json'
        unique [:command, :key]
      end
    end

    def self.migrate!(db)
      return if db.schema(:pins).any? { |column, _| column == :value_format }

      db.transaction(mode: :immediate) do
        db.alter_table(:pins) { add_column :value_format, String, null: false, default: 'json' }
        db[:pins].update(value_format: 'legacy')
      end
    end

    def legacy? = value_format == 'legacy'

    # Raw legacy JSON can also have been a String; only its typed source resolves this.
    def legacy_ambiguous?
      return false unless legacy? && !value_json.nil?

      ::JSON.parse(value_json)
      true
    rescue ::JSON::ParserError
      false
    end

    def value
      Hiiro::DB::JSON.load(value_json)
    rescue ::JSON::ParserError
      raise unless legacy?

      value_json
    end

    def value=(v)
      self.value_json = ::JSON.generate(v)
      self.value_format = 'json'
    end

    def self.set(command, key, value)
      db.transaction(mode: :immediate) do
        row = find_key(command, key) || new(command: command.to_s, key: key.to_s)
        row.value = value
        row.save_changes
        row
      end
    end

    def self.remove(command, key)
      db.transaction(mode: :immediate) do
        row = find_key(command, key)
        where(id: row.id).delete if row
        row
      end
    end

    def self.for_command(cmd) = where(command: cmd.to_s).all
    def self.find_key(cmd, key) = where(command: cmd.to_s, key: key.to_s).first
  end
end
