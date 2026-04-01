require 'sequel'

class Hiiro
  class RegistryEntry < Sequel::Model(:registry_entries)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:registry_entries) do
        primary_key :id
        String :resource_type, null: false   # e.g. "service", "queue", "worker"
        String :name,          null: false   # canonical identifier
        String :short_name                   # alias / shorthand
        String :description
        String :meta_json                    # arbitrary JSON for extra fields
        String :created_at
        unique [:resource_type, :name]
        unique [:resource_type, :short_name], where: Sequel[short_name: nil].~
      end
    end

    # ── Finders ──────────────────────────────────────────────────────────────

    def self.of_type(type)       = where(resource_type: type.to_s).order(:name).all
    def self.all_ordered         = order(:resource_type, :name).all
    def self.known_types         = distinct.select_map(:resource_type).sort

    # Resolve by exact name or short_name within a type (or globally).
    def self.find_by_ref(ref, type: nil)
      scope = type ? where(resource_type: type.to_s) : self
      scope.where(name: ref).first || scope.where(short_name: ref).first
    end

    # Fuzzy-finder display lines: "type  short  name  description"
    def self.fuzzy_lines(type: nil)
      entries = type ? of_type(type) : all_ordered
      entries.map(&:fuzzy_line)
    end

    # ── Instance helpers ─────────────────────────────────────────────────────

    def meta
      return {} unless meta_json
      Hiiro::DB::JSON.load(meta_json) || {}
    rescue
      {}
    end

    def meta=(h)
      self.meta_json = Hiiro::DB::JSON.dump(h)
    end

    def fuzzy_line
      parts = [resource_type.ljust(14), short_name&.ljust(16) || ' ' * 16, name]
      parts << "  # #{description}" if description && !description.empty?
      parts.join('  ').strip
    end

    def display
      lines = ["#{resource_type} / #{name}"]
      lines << "  alias:  #{short_name}"       if short_name
      lines << "  desc:   #{description}"      if description
      meta.each { |k, v| lines << "  #{k}: #{v}" } unless meta.empty?
      lines.join("\n")
    end
  end
end
