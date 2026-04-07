require 'sequel'

class Hiiro
  class RegistryEntry < Sequel::Model(:registry_entries)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:registry_entries) do
        primary_key :id
        String :resource_type, null: false   # e.g. "service", "queue", "worker"
        String :name,          null: false   # canonical identifier
        String :value                        # stored value (optional)
        String :short_name                   # alias / shorthand
        String :description
        String :meta_json                    # arbitrary JSON for extra fields
        String :created_at
        unique [:resource_type, :name]
        unique [:resource_type, :short_name], where: Sequel[short_name: nil].~
      end
    end

    def self.migrate!(db)
      # Add value column if missing (migration for existing DBs)
      unless db.schema(:registry_entries).any? { |col, _| col == :value }
        db.alter_table(:registry_entries) { add_column :value, String }
      end
    end

    # ── Finders ──────────────────────────────────────────────────────────────

    def self.of_type(type)       = where(resource_type: type.to_s).order(:name).all
    def self.all_ordered         = order(:resource_type, :name).all
    def self.known_types         = distinct.select_map(:resource_type).sort

    # Resolve by exact name, short_name, or prefix within a type (or globally).
    # Returns single entry or nil. Ambiguous prefix matches return nil.
    def self.find_by_ref(ref, type: nil, substring: false)
      scope = type ? where(resource_type: type.to_s) : self
      
      # Try exact match first (name or short_name)
      exact = scope.where(name: ref).first || scope.where(short_name: ref).first
      return exact if exact
      
      # Fall back to prefix/substring matching
      entries = scope.all
      matcher = Hiiro::Matcher.new(entries, :name)
      result = substring ? matcher.by_substring(ref) : matcher.by_prefix(ref)
      
      # Only return if unambiguous (exactly one match)
      return result.first.item if result.one?
      
      # Also try matching against short_name
      matcher_short = Hiiro::Matcher.new(entries.select(&:short_name), :short_name)
      result_short = substring ? matcher_short.by_substring(ref) : matcher_short.by_prefix(ref)
      return result_short.first.item if result_short.one?
      
      nil
    end
    
    # Find all entries matching ref (for showing ambiguous matches)
    # Checks both name and short_name, returns unique entries
    def self.find_all_by_ref(ref, type: nil, substring: false)
      scope = type ? where(resource_type: type.to_s) : self
      
      # Check for exact matches first
      exact = scope.where(name: ref).all + scope.where(short_name: ref).all
      return exact.uniq(&:id) if exact.any?
      
      # Fall back to prefix/substring matching on name
      entries = scope.all
      matcher = Hiiro::Matcher.new(entries, :name)
      result = substring ? matcher.by_substring(ref) : matcher.by_prefix(ref)
      name_matches = result.matches.map(&:item)
      
      # Also match on short_name
      matcher_short = Hiiro::Matcher.new(entries.select(&:short_name), :short_name)
      result_short = substring ? matcher_short.by_substring(ref) : matcher_short.by_prefix(ref)
      short_matches = result_short.matches.map(&:item)
      
      (name_matches + short_matches).uniq(&:id)
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
      parts << " = #{value}" if value && !value.empty?
      parts << "  # #{description}" if description && !description.empty?
      parts.join('  ').strip
    end

    def display
      lines = ["#{resource_type} / #{name}"]
      lines << "  value:  #{value}"            if value
      lines << "  alias:  #{short_name}"       if short_name
      lines << "  desc:   #{description}"      if description
      meta.each { |k, v| lines << "  #{k}: #{v}" } unless meta.empty?
      lines.join("\n")
    end
  end
end

class Hiiro
  # Pick a registry entry by fuzzyfinder. Returns the canonical name string, or nil.
  # Usage inside a subcommand block:
  #   task = opts.task || registry_pick('isc_task')
  def registry_pick(type = nil)
    lines = Hiiro::RegistryEntry.fuzzy_lines(type: type)
    return nil if lines.empty?
    chosen = fuzzyfind(lines)
    return nil unless chosen
    # fuzzy_line format: "type  short  name  # desc" — name is 3rd column
    chosen.strip.split(/\s{2,}/)[2]
  end
end
