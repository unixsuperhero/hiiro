require 'yaml'
require 'sequel'

class Hiiro
  class TodoItem < Sequel::Model(:todos)
    Hiiro::DB.register(self)
    unrestrict_primary_key

    STATUSES = %w[not_started started done skip].freeze

    def self.create_table!(db)
      db.create_table?(:todos) do
        primary_key :id
        String :text, null: false
        String :status, default: 'not_started'
        String :tags
        String :task_name
        String :subtask_name
        String :tree
        String :branch
        String :session
        String :created_at
        String :updated_at
      end
    end

    def initialize(values = OPTS)
      super
      self.status = STATUSES.include?(status.to_s) ? status : 'not_started'
      self.created_at ||= Time.now.to_s
    end

    def before_create
      self.updated_at ||= created_at
      super
    end

    def tags_list
      return [] if tags.nil? || tags.empty?
      tags.split(',').map(&:strip)
    end

    def has_tag?(tag)
      tags_list.any? { |t| t.downcase == tag.downcase }
    end

    def add_tag(tag)
      current = tags_list
      return if current.any? { |t| t.downcase == tag.downcase }
      current << tag
      self.tags = current.join(', ')
    end

    def remove_tag(tag)
      current = tags_list.reject { |t| t.downcase == tag.downcase }
      self.tags = current.empty? ? nil : current.join(', ')
    end

    def has_task_info?
      !task_name.nil? || !subtask_name.nil?
    end

    def full_task_name
      return nil unless has_task_info?
      subtask_name ? "#{task_name}/#{subtask_name}" : task_name
    end

    def update_status(new_status)
      return false unless STATUSES.include?(new_status)
      self.status = new_status
      self.updated_at = Time.now.to_s
      true
    end

    def to_h
      h = {
        'id' => id,
        'text' => text,
        'status' => status,
        'created_at' => created_at,
        'updated_at' => updated_at
      }
      h['tags'] = tags if tags && !tags.empty?
      h['task_name'] = task_name if task_name
      h['subtask_name'] = subtask_name if subtask_name
      h['tree'] = tree if tree
      h['branch'] = branch if branch
      h['session'] = session if session
      h
    end

    def self.from_h(h)
      new(
        id: h['id'],
        text: h['text'],
        status: h['status'],
        tags: h['tags'],
        task_name: h['task_name'],
        subtask_name: h['subtask_name'],
        tree: h['tree'],
        branch: h['branch'],
        session: h['session'],
        created_at: h['created_at'],
        updated_at: h['updated_at']
      )
    end

    def match?(query)
      query = query.downcase
      text.downcase.include?(query) ||
        tags_list.any? { |t| t.downcase.include?(query) } ||
        (task_name && task_name.downcase.include?(query)) ||
        (subtask_name && subtask_name.downcase.include?(query)) ||
        (tree && tree.downcase.include?(query)) ||
        (branch && branch.downcase.include?(query))
    end
  end

  class TodoManager
    ITEM_TEMPLATE = { 'text' => '', 'status' => 'not_started', 'tags' => nil }.freeze
    EDITABLE_FIELDS = %w[text status tags].freeze
    class EditConflict < StandardError; end

    def all
      TodoItem.order(:id).all
    end
    alias items all

    def find(id)
      TodoItem[id.to_i] || items.find { |item| item.id.to_s.end_with?(id.to_s) }
    end

    def find_by_index(index)
      items[index.to_i]
    end

    def add(text, tags: nil, task_info: nil)
      TodoItem.create(text: text, tags: tags, **(task_info || {}))
    end

    def edit_items(items_to_edit = nil, task_info: nil, hiiro:)
      selected = items_to_edit.nil? ? [] : Array(items_to_edit)
      baseline = selected.to_h { |item| [item.id, item.values.dup] }
      projection = items_to_edit.nil? ? [ITEM_TEMPLATE.dup] : selected.map { |item| editable_hash(item) }
      input = InputFile.yaml_file(hiiro: hiiro, content: projection.to_yaml, prefix: 'todo-edit-')
      document = input.edit.document
      raise ArgumentError, "Invalid todo YAML: #{document.error.message}" unless document.valid?
      return [] if document.empty? || !document.changed?
      data = document.data
      rows = data.is_a?(Hash) ? [data] : data
      raise ArgumentError, 'Todo editor requires a YAML list of records' unless rows.is_a?(Array)
      validate_edit_rows!(rows, baseline)
      if items_to_edit.nil?
        rows.map { |row| new_item(row, task_info) }
      else
        apply_edit(rows, baseline, task_info)
      end
    ensure
      input&.cleanup
    end

    def add_items(new_items)
      raise ArgumentError, 'New todos cannot specify IDs' unless new_items.all? { |item| item.new? && item.id.nil? }
      TodoItem.db.transaction { new_items.each(&:save) }
      new_items
    end

    def remove(id)
      item = find(id)
      return nil unless item
      item.delete
      item
    end

    def change(id, **changes)
      item = find(id)
      return nil unless item
      changes.each do |field, value|
        raise ArgumentError, "Unknown todo field: #{field}" unless EDITABLE_FIELDS.include?(field.to_s)
        next if field == :status && !TodoItem::STATUSES.include?(value)
        item[field] = value
      end
      if item.modified?
        item.updated_at = Time.now.to_s
        item.save_changes
      end
      item
    end

    def start(id)
      change(id, status: 'started')
    end

    def done(id)
      change(id, status: 'done')
    end

    def skip(id)
      change(id, status: 'skip')
    end

    def reset(id)
      change(id, status: 'not_started')
    end

    def search(query)
      items.select { |item| item.match?(query) }
    end

    def filter_by_status(*statuses)
      TodoItem.where(status: statuses).order(:id).all
    end

    def filter_by_tag(tag)
      items.select { |item| item.has_tag?(tag) }
    end

    def filter_by_task(task_name)
      items.select { |item| item.task_name == task_name || item.full_task_name == task_name }
    end

    def active
      filter_by_status('not_started', 'started')
    end

    def completed
      filter_by_status('done', 'skip')
    end

    def list(items_to_show = nil, show_all: false)
      items_to_show ||= show_all ? all : active
      return "No todo items found." if items_to_show.empty?
      items_to_show.map { |item| format_item(item) }.join("\n")
    end

    def format_item(item)
      status_icon = case item.status
        when 'not_started' then '[ ]'
        when 'started' then '[>]'
        when 'done' then '[x]'
        when 'skip' then '[-]'
      end
      line = "#{item.id} #{status_icon} #{item.text}"
      line += "  [#{item.tags}]" if item.tags && !item.tags.empty?
      line += "  (#{item.full_task_name})" if item.has_task_info?
      line
    end

    private

    def editable_hash(item)
      { 'id' => item.id, 'text' => item.text, 'status' => item.status, 'tags' => item.tags }
    end

    def validate_edit_rows!(rows, baseline)
      ids = []
      rows.each do |row|
        raise ArgumentError, 'Each todo must be a mapping' unless row.is_a?(Hash)
        unknown = row.keys - EDITABLE_FIELDS - ['id']
        raise ArgumentError, "Unknown todo fields: #{unknown.join(', ')}" unless unknown.empty?
        if row.key?('id')
          id = row['id']
          raise ArgumentError, 'Existing todo IDs must be unchanged positive integers' unless id.is_a?(Integer) && baseline.key?(id) && !ids.include?(id)
          ids << id
        elsif !row['text'].is_a?(String) || row['text'].strip.empty?
          raise ArgumentError, 'New todo text cannot be blank'
        end
        if row.key?('text') && (!row['text'].is_a?(String) || row['text'].strip.empty?)
          raise ArgumentError, 'Todo text cannot be blank'
        end
        if row.key?('status') && !TodoItem::STATUSES.include?(row['status'])
          raise ArgumentError, 'Invalid todo status'
        end
        if row.key?('tags') && !row['tags'].nil? && !row['tags'].is_a?(String)
          raise ArgumentError, 'Todo tags must be a string or null'
        end
      end
    end

    def new_item(row, task_info)
      TodoItem.new(row.transform_keys(&:to_sym).merge(task_info || {}))
    end

    def apply_edit(rows, baseline, task_info)
      TodoItem.db.transaction(mode: :immediate) do
        retained = rows.filter_map { |row| row['id'] }
        (baseline.keys - retained).each do |id|
          current = TodoItem[id]
          next unless current
          raise EditConflict, "Todo #{id} changed while editing; deletion cancelled" unless current.values == baseline[id]
          current.delete
        end
        rows.map do |row|
          next new_item(row, task_info).save unless row.key?('id')
          id = row['id']
          changes = row.reject { |field, value| field == 'id' || value == baseline[id][field.to_sym] }
          current = TodoItem[id]
          next current if changes.empty?
          raise EditConflict, "Todo #{id} was removed while editing" unless current
          changes.each do |field, value|
            unless current[field.to_sym] == baseline[id][field.to_sym] || current[field.to_sym] == value
              raise EditConflict, "Todo #{id} #{field} changed while editing"
            end
            current[field.to_sym] = value
          end
          if current.modified?
            current.updated_at = Time.now.to_s
            current.save_changes
          end
          current
        end.compact
      end
    end
  end
end
