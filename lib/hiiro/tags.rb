class Hiiro
  # Shared tag store, keyed by namespace (e.g. :branch, :task).
  # Stored in ~/.config/hiiro/tags.yml as { namespace => { key => [tags] } }.
  class Tags
    FILE = Hiiro::Config.path('tags.yml')

    def initialize(namespace)
      @namespace = namespace.to_s
    end

    # Returns the tag array for a given key ([] if none).
    def get(key)
      Array(load.dig(@namespace, key.to_s))
    end

    # Adds tags to a key (idempotent). Returns the new tag array.
    def add(key, *tags)
      data = load
      data[@namespace] ||= {}
      current = Array(data.dig(@namespace, key.to_s))
      data[@namespace][key.to_s] = (current + tags.map(&:to_s)).uniq
      save(data)
      data[@namespace][key.to_s]
    end

    # Removes specific tags from a key. Pass no tags to clear all.
    def remove(key, *tags)
      data = load
      data[@namespace] ||= {}
      current = Array(data.dig(@namespace, key.to_s))
      updated = tags.empty? ? [] : (current - tags.map(&:to_s))
      if updated.empty?
        data[@namespace].delete(key.to_s)
      else
        data[@namespace][key.to_s] = updated
      end
      save(data)
    end

    # Returns the full { key => [tags] } hash for this namespace.
    def all
      load[@namespace] || {}
    end

    # Returns all distinct tag values used in this namespace.
    def known_tags
      all.values.flatten.uniq.sort
    end

    # Formats a tag array as colored badges for terminal output.
    def self.badges(tags)
      Array(tags).map { |t| "\e[30;104m#{t}\e[0m" }.join(' ')
    end

    private

    def load
      return {} unless File.exist?(FILE)
      YAML.safe_load(File.read(FILE)) || {}
    rescue
      {}
    end

    def save(data)
      data.each { |_, v| v.reject! { |_, tags| tags.nil? || tags.empty? } if v.is_a?(Hash) }
      data.reject! { |_, v| v.nil? || v.empty? }
      FileUtils.mkdir_p(File.dirname(FILE))
      File.write(FILE, data.to_yaml)
    end
  end
end
