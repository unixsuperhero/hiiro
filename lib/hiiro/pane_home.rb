require 'sequel'

class Hiiro
  class PaneHome < Sequel::Model(:pane_homes)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:pane_homes) do
        primary_key :id
        String :name, null: false
        String :data_json  # JSON: { session: "...", path: "..." }
        unique :name
      end
    end

    def data     = Hiiro::DB::JSON.load(data_json) || {}
    def data=(v) ; self.data_json = Hiiro::DB::JSON.dump(v); end

    def self.find_by_name(n) = where(name: n.to_s).first
    def self.all_as_hash
      all.each_with_object({}) { |ph, h| h[ph.name] = ph.data }
    end
  end
end
