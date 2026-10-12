require 'sequel'
require_relative 'alias_editor'

class Hiiro
  class AppRecord < Sequel::Model(:apps)
    Hiiro::DB.register(self)
    extend AliasEditor

    def self.create_table!(db)
      db.create_table?(:apps) do
        primary_key :id
        String :name, null: false
        String :path, null: false
        unique :name
      end
    end

    def self.find_by_name(n) = where(name: n.to_s).first
    def self.all_as_hash = all.each_with_object({}) { |a, h| h[a.name] = a.path }
  end
end
