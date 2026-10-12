require 'sequel'

class Hiiro
  class PaneHome < Sequel::Model(:pane_homes)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:pane_homes) do
        primary_key :id
        String :name, null: false
        String :data_json
        unique :name
      end
    end

    def data     = Hiiro::DB::JSON.load(data_json) || {}
    def data=(v) ; self.data_json = Hiiro::DB::JSON.dump(v); end

    def self.find_by_name(n) = where(name: n.to_s).first

    def self.set(name, **fields)
      db.transaction(mode: :immediate) do
        row = find_by_name(name) || new(name: name.to_s)
        row.data = row.data.merge(fields.transform_keys(&:to_s))
        row.save_changes
        row
      end
    end

    def self.remove(name)
      db.transaction(mode: :immediate) do
        row = find_by_name(name)
        where(id: row.id).delete if row
        row
      end
    end

    def self.all_as_hash
      all.each_with_object({}) { |ph, h| h[ph.name] = ph.data }
    end
  end
end
