require 'yaml'
require 'fileutils'
require 'tempfile'

class Hiiro
  class TodoItem
    STATUSES = %w[not_started started done skip].freeze

    attr_accessor :id, :text, :status, :tags
    attr_accessor :task_name, :subtask_name, :tree, :branch, :session
    attr_accessor :created_at, :updated_at

    def initialize(
      id: nil,
      text:,
      status: 'not_started',
      tags: nil,
      task_name: nil,
      subtask_name: nil,
      tree: nil,
      branch: nil,
      session: nil,
      created_at: nil,
      updated_at: nil
    )
      @id = id
      @text = text
      @status = STATUSES.include?(status) ? status : 'not_started'
      @tags = tags
      @task_name = task_name
      @subtask_name = subtask_name
      @tree = tree
      @branch = branch
      @session = session
      @created_at = created_at || Time.now.to_s
      @updated_at = updated_at || @created_at
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
      @tags = current.join(', ')
    end

    def remove_tag(tag)
      current = tags_list.reject { |t| t.downcase == tag.downcase }
      @tags = current.empty? ? nil : current.join(', ')
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
      @status = new_status
      @updated_at = Time.now.to_s
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
    TODO_FILE = File.join(Dir.home, '.config', 'hiiro', 'todo.yml')

    ITEM_TEMPLATE = {
      'text' => '',
      'status' => 'not_started',
      'tags' => nil
    }.freeze

    attr_reader :items, :todo_file

    def initialize(file_path: nil)
      @todo_file = file_path || TODO_FILE
      @file_path = @todo_file
      @items, @next_id = load_items
    end

    def next_id!
      id = @next_id
      @next_id += 1
      id
    end

    # --- High-level API ---

    def all
      items
    end

    def find(id)
      id_int = id.to_i
      items.find { |item| item.id == id_int }
    end

    def find_by_index(index)
      items[index.to_i]
    end

    def add(text, tags: nil, task_info: nil)
      item = TodoItem.new(
        id: next_id!,
        text: text,
        tags: tags,
        task_name: task_info&.dig(:task_name),
        subtask_name: task_info&.dig(:subtask_name),
        tree: task_info&.dig(:tree),
        branch: task_info&.dig(:branch),
        session: task_info&.dig(:session)
      )
      @items << item
      save
      item
    end

    def edit_items(items_to_edit = nil, task_info: nil)
      items_array = if items_to_edit.nil?
        [ITEM_TEMPLATE.dup]
      elsif items_to_edit.is_a?(Array)
        items_to_edit.map { |item| item.is_a?(TodoItem) ? editable_hash(item) : item }
      else
        [items_to_edit.is_a?(TodoItem) ? editable_hash(items_to_edit) : items_to_edit]
      end

      tmpfile = Tempfile.new(['todo-edit-', '.yml'])
      tmpfile.write(items_array.to_yaml)
      tmpfile.close

      editor = ENV['EDITOR'] || 'safe_nvim' || 'nvim'
      system(editor, tmpfile.path)

      updated_data = YAML.safe_load_file(tmpfile.path)
      tmpfile.unlink

      return [] if updated_data.nil?

      updated_array = updated_data.is_a?(Array) ? updated_data : [updated_data]
      updated_array.filter_map do |h|
        next if h['text'].nil? || h['text'].to_s.strip.empty?
        TodoItem.new(
          id: next_id!,
          text: h['text'],
          status: h['status'] || 'not_started',
          tags: h['tags'],
          task_name: task_info&.dig(:task_name),
          subtask_name: task_info&.dig(:subtask_name),
          tree: task_info&.dig(:tree),
          branch: task_info&.dig(:branch),
          session: task_info&.dig(:session)
        )
      end
    end

    def add_items(new_items)
      @items.concat(new_items)
      save
      new_items
    end

    def remove(id_or_index)
      item = resolve_item(id_or_index)
      return nil unless item
      @items.delete(item)
      save
      item
    end

    def change(id_or_index, text: nil, tags: nil, status: nil)
      item = resolve_item(id_or_index)
      return nil unless item

      item.text = text if text
      item.tags = tags if tags
      item.update_status(status) if status
      item.updated_at = Time.now.to_s
      save
      item
    end

    def start(id_or_index)
      change_status(id_or_index, 'started')
    end

    def done(id_or_index)
      change_status(id_or_index, 'done')
    end

    def skip(id_or_index)
      change_status(id_or_index, 'skip')
    end

    def reset(id_or_index)
      change_status(id_or_index, 'not_started')
    end

    def search(query)
      items.select { |item| item.match?(query) }
    end

    def filter_by_status(*statuses)
      items.select { |item| statuses.include?(item.status) }
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

    # --- List display ---

    def list(items_to_show = nil, show_all: false)
      items_to_show ||= show_all ? all : active
      return "No todo items found." if items_to_show.empty?

      lines = items_to_show.map { |item| format_item(item) }
      lines.join("\n")
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

    def resolve_item(id)
      find(id)
    end

    def change_status(id_or_index, status)
      item = resolve_item(id_or_index)
      return nil unless item
      item.update_status(status)
      save
      item
    end

    def editable_hash(item)
      {
        'text' => item.text,
        'status' => item.status,
        'tags' => item.tags
      }
    end

    def load_items
      return [[], 1] unless File.exist?(@file_path)

      data = YAML.safe_load_file(@file_path) || {}
      items = (data['todos'] || []).map { |h| TodoItem.from_h(h) }
      next_id = data['next_id'] || (items.map { |i| i.id.to_i }.max || 0) + 1
      [items, next_id]
    end

    def save
      FileUtils.mkdir_p(File.dirname(@file_path))
      data = { 'next_id' => @next_id, 'todos' => items.map(&:to_h) }
      File.write(@file_path, YAML.dump(data))
    end
  end
end
