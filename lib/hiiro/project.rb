require 'sequel'

class Hiiro
  class Project < Sequel::Model(:projects)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:projects) do
        primary_key :id
        String :name, null: false
        String :path, null: false
        unique :name
      end
    end

    def self.find_by_name(n) = where(name: n.to_s).first
    def self.all_as_hash = all.each_with_object({}) { |p, h| h[p.name] = p.path }
  end
end
