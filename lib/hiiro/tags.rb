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
        return tags if terms.empty?

        conditions = terms.map { |q| Sequel.like(:name, "%#{q}%") }
        tags.where(Sequel.|(*conditions))
      end

      def search(*terms, type: nil)
        tags = type ? where(taggable_type: type).select(:name).distinct : all_tags
        filter(terms.flatten, tags).order(:name).select_map(:name)
      end

      def tags_by_type(type=nil)
        tags = type ? where(taggable_type: type).select(:name).distinct : all_tags
        tags.order(:name).select_map(:name)
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

      # Idempotent tag assignment, isolated from other objects and writers.
      def tag!(obj, *tag_names)
        db.transaction(mode: :immediate) do
          t = obj.class.name.split('::').last
          tag_names.each do |name|
            find_or_create(
              name: name.to_s,
              taggable_type: t,
              taggable_id: obj.id.to_s
            ) { |tag| tag.created_at = Time.now.iso8601 }
          end
        end
      end

      # Remove only the requested tags from this object.
      def untag!(obj, *tag_names)
        db.transaction(mode: :immediate) do
          self.for(obj).where(name: tag_names.map(&:to_s)).delete
        end
      end
    end

    def taggable
      case taggable_type
      when 'Branch' then Hiiro::Branch.find_by_name(taggable_id)
      when 'Task' then Hiiro::TaskRecord.find_by_name(taggable_id)
      else
        return unless Hiiro.const_defined?(taggable_type, false)

        klass = Hiiro.const_get(taggable_type, false)
        klass[taggable_id] if klass.is_a?(Class) && klass < Sequel::Model
      end
    end
  end

  # Branch and Task keys are names; model namespaces retain their row IDs.
  class Tags
    NAMESPACE_TO_TYPE = {
      'branch' => 'Branch',
      'task' => 'Task',
      'link' => 'Link',
      'pr' => 'PinnedPr',
      'pinned_pr' => 'PinnedPr',
      'task_record' => 'TaskRecord',
      'registry_entry' => 'RegistryEntry',
    }.freeze

    def initialize(namespace)
      @type_name = NAMESPACE_TO_TYPE.fetch(namespace.to_s)
    end

    def get(key)
      Hiiro::Tag.where(taggable_type: @type_name, taggable_id: key.to_s).map(&:name)
    end

    # Adds tags to a key (idempotent). Returns the new tag array.
    def add(key, *tags)
      Hiiro::Tag.db.transaction(mode: :immediate) do
        tags.each do |tag_name|
          Hiiro::Tag.find_or_create(
            name: tag_name.to_s,
            taggable_type: @type_name,
            taggable_id: key.to_s
          ) { |t| t.created_at = Time.now.iso8601 }
        end
        get(key)
      end
    end

    # Removes specific tags from a key. Pass no tags to clear this key only.
    def remove(key, *tags)
      Hiiro::Tag.db.transaction(mode: :immediate) do
        rows = Hiiro::Tag.where(taggable_type: @type_name, taggable_id: key.to_s)
        rows = rows.where(name: tags.map(&:to_s)) unless tags.empty?
        rows.delete
      end
    end

    def all
      Hiiro::Tag.where(taggable_type: @type_name)
        .each_with_object({}) do |t, h|
          h[t.taggable_id] ||= []
          h[t.taggable_id] << t.name
        end
    end

    def known_tags
      Hiiro::Tag.where(taggable_type: @type_name).distinct.select_map(:name).sort
    end

    def self.badges(tags)
      Array(tags).map { |t| "\e[30;104m#{t}\e[0m" }.join(' ')
    end
  end
end
