require 'sequel'

class Hiiro
  class Tag < Sequel::Model(:tags)
    Hiiro::DB.register(self)

    class << self
      def create_table!(db)
        db.create_table?(:tags) do
          primary_key :id
          String :name, null: false           # tag value, e.g. "oncall"
          String :taggable_type, null: false  # e.g. "Branch", "PinnedPr", "Task"
          String :taggable_id, null: false    # string id of tagged object
          String :created_at
          unique [:name, :taggable_type, :taggable_id]
        end
      end

      def all_tags
        select(:name).distinct
      end

      def filter(terms, tags=all_tags)
        tags.select{|tag|
          terms.any?{|term| tag.start_with?(term) }
        }
      end

      def search(*terms, type: nil)
          filter(terms.flatten, tags_by_type(type))
      end

      # Returns all Tag rows for a given object
      def tags_by_type(type=nil)
        return all_tags if type.nil?

        where(taggable_type: type.to_s).select(:name).distinct.map(&:name).sort
      end

      # Returns all Tag rows for a given object
      def for(obj)
        t = obj.class.name.split('::').last
        where(taggable_type: t, taggable_id: obj.id.to_s)
      end

      # Returns all Tag rows with a given name
      def named(tag_name)
        where(name: tag_name.to_s)
      end

      def tagged_by_type(tag, type)
        where(name: tag, taggable_type: type).map(&:taggable)
      end

      # Returns all tagged objects across all types for a tag name
      def everything_tagged(tag_name)
        named(tag_name).map(&:taggable).compact
      end

      # Idempotent tag assignment
      def tag!(obj, *tag_names)
        t = obj.class.name.split('::').last
        tag_names.each do |name|
          find_or_create(
            name: name.to_s,
            taggable_type: t,
            taggable_id: obj.id.to_s
          ) { |tag| tag.created_at = Time.now.iso8601 }
        end
      end

      # Remove tags from an object
      def untag!(obj, *tag_names)
        t = obj.class.name.split('::').last
        where(
          taggable_type: t,
          taggable_id: obj.id.to_s,
          name: tag_names.map(&:to_s)
        ).delete
      end
    end

    # Polymorphic accessor — returns the tagged object
    def taggable
      klass = Hiiro.const_get(taggable_type) rescue nil
      klass&.[](taggable_id)
    end
  end

  # Shared tag store, keyed by namespace (e.g. :branch, :task).
  # Delegates to Hiiro::Tag internally; maintains tags.yml as a backup.
  class Tags
    FILE = Hiiro::Config.path('tags.yml')

    def initialize(namespace, fs: Hiiro::Effects::Filesystem.new)
      @namespace = namespace.to_s
      @fs = fs
    end

    # Returns the tag array for a given key ([] if none).
    def get(key)
      Hiiro::Tag.where(taggable_type: type_name, taggable_id: key.to_s).map(&:name)
    end

    # Adds tags to a key (idempotent). Returns the new tag array.
    def add(key, *tags)
      tags.each do |tag_name|
        Hiiro::Tag.find_or_create(
          name: tag_name.to_s,
          taggable_type: type_name,
          taggable_id: key.to_s
        ) { |t| t.created_at = Time.now.iso8601 }
      end
      get(key).tap { save_yaml_backup }
    end

    # Removes specific tags from a key. Pass no tags to clear all.
    def remove(key, *tags)
      if tags.empty?
        Hiiro::Tag.where(taggable_type: type_name, taggable_id: key.to_s).delete
      else
        Hiiro::Tag.where(
          taggable_type: type_name,
          taggable_id: key.to_s,
          name: tags.map(&:to_s)
        ).delete
      end
      save_yaml_backup
    end

    # Returns the full { key => [tags] } hash for this namespace.
    def all
      Hiiro::Tag.where(taggable_type: type_name)
        .each_with_object({}) do |t, h|
          h[t.taggable_id] ||= []
          h[t.taggable_id] << t.name
        end
    end

    # Returns all distinct tag values used in this namespace.
    def known_tags
      Hiiro::Tag.where(taggable_type: type_name).distinct.pluck(:name).sort
    end

    # Formats a tag array as colored badges for terminal output.
    def self.badges(tags)
      Array(tags).map { |t| "\e[30;104m#{t}\e[0m" }.join(' ')
    end

    private

    def type_name
      # :branch → "Branch", :pinned_pr → "PinnedPr", etc.
      @namespace.to_s.split('_').map(&:capitalize).join
    end

    def save_yaml_backup
      return unless Hiiro::DB.dual_write?
      data = {}
      Hiiro::Tag.all.each do |t|
        ns = t.taggable_type.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, '')
        data[ns] ||= {}
        data[ns][t.taggable_id] ||= []
        data[ns][t.taggable_id] << t.name
      end
      data.each { |_, v| v.each { |_, tags| tags.uniq! } }
      @fs.write(FILE, data.to_yaml)
    rescue => e
      warn "Tags YAML backup failed: #{e}"
    end
  end
end
