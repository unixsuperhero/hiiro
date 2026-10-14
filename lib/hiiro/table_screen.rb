require 'set'

class Hiiro
  # The `h table` TUI: every registry table (or one) in a scope, with a detail
  # pane, prompts for edits, marks for bulk actions, and per-table action letters.
  class TableScreen < Tui::Screen
    KEY_HINT = '[/]search [@]table [g]scope [a]dd [r]ename [e]dit [d]elete [T]ag [m]ove [space]mark [o]pen [y]ank [q]uit'.freeze

    key 'g', :toggle_scope
    key ' ', :toggle_mark
    key 'a', :add_entry
    key 'r', :rename_entry
    key 'R', :rename_table
    key 'e', :edit_value
    key 'd', :delete_targets
    key 'T', :tag_targets
    key 'm', :move_targets
    key '@', :pick_table

    attr_reader :scope, :table, :actions, :marked

    def initialize(scope: TableScope.current, table: nil, actions: TableActions.load)
      @scope = scope
      @table = table
      @actions = actions
      @marked = Set.new
      super(items: [], empty_message: 'No entries.')
      reload!
    end

    # Keeps the cursor on the same entry when it is still listed.
    def reload!
      current_id = current_item&.id
      dataset = table ? RegistryEntry.where(resource_type: table) : RegistryEntry.dataset
      @items = scope.apply(dataset).order(:resource_type, :name).all
      ids = @items.map { |entry| entry.id.to_s }
      @tags = Tag.where(taggable_type: 'RegistryEntry', taggable_id: ids).order(:name)
        .select_map([:taggable_id, :name])
        .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      @marked &= @items.map(&:id).to_set
      index = current_id && filtered_items.index { |entry| entry.id == current_id }
      state.cursor = index if index
      move(0)
    end

    def tags_for(entry) = @tags.fetch(entry.id.to_s, [])

    def row_text(entry)
      mark = marked.include?(entry.id) ? '*' : ' '
      tags = tags_for(entry).map { |tag| " ##{tag}" }.join
      "#{mark} #{entry.resource_type.ljust(8)} #{entry.name.ljust(16)} #{entry.value}#{tags}"
    end

    def format_row(entry, current, line_cols) = super(row_text(entry), current, line_cols)

    def max_horizontal_offset(line_cols = nil, visible = nil)
      super(line_cols, (visible || window_items).map { |entry| row_text(entry) })
    end

    def header_lines
      ["tables  scope:#{scope.label}  table:#{table || '*'}", KEY_HINT]
    end

    def detail_lines(entry)
      task = entry.task_id && TaskRecord[entry.task_id]
      [
        "table  #{entry.resource_type}",
        "name   #{entry.name}",
        "short  #{entry.short_name}",
        "desc   #{entry.description}",
        "value  #{entry.value}",
        "tags   #{tags_for(entry).join(' ')}",
        "task   #{task ? task.name : '-'}",
        '',
        'actions:',
        *actions.for(entry).map { |letter, command| "  #{letter}  #{command}" },
      ]
    end

    def match?(entry, query)
      fields = [entry.name, entry.value, entry.description, entry.short_name, *tags_for(entry)]
      fields.compact.join(' ').downcase.include?(query.downcase)
    end

    def pick_table
      prompt('table', complete: { '' => -> { Table.all.map(&:name) } }) do |name|
        next if name.strip.empty?

        @table = name.strip
        reload!
        state.cursor = 0
        move(0)
      end
    end

    def unhandled_key(key)
      entry = current_item
      return unless entry && key.is_a?(String) && key.length == 1
      return unless actions.for(entry).key?(key)

      self.message = "ran: #{actions.run(key, entry)}"
    end

    private

    def toggle_scope
      toggled = scope.toggle
      if toggled.equal?(scope)
        self.message = 'no current task to scope to'
        return
      end

      @scope = toggled
      reload!
      state.cursor = 0
      move(0)
      self.message = "scope: #{scope.label}"
    end

    def toggle_mark
      entry = current_item
      return unless entry

      marked.include?(entry.id) ? marked.delete(entry.id) : marked.add(entry.id)
      move(1)
    end

    def targets
      chosen = items.select { |entry| marked.include?(entry.id) }
      chosen.empty? ? [current_item].compact : chosen
    end

    def add_entry
      prompt('name') do |name|
        next if name.empty?

        prompt('value') do |value|
          prompt('table', default: table || current_item&.resource_type, complete: { '' => -> { Completions.tables } }) do |table_name|
            next if table_name.empty?

            create_entry(table_name, name, value)
          end
        end
      end
    end

    def create_entry(table_name, name, value)
      Table.named(table_name).add(name, value:, task_id: scope.task? ? scope.task.id : nil)
      reload!
      self.message = "added #{table_name}/#{name}"
    rescue Sequel::UniqueConstraintViolation
      self.message = "exists: #{table_name}/#{name}"
    end

    def rename_entry
      entry = current_item
      return unless entry

      prompt("rename #{entry.name} to") do |name|
        next if name.empty?

        mutate { entry.update(name:) }
      end
    end

    def rename_table
      entry = current_item
      return unless entry

      old_name = entry.resource_type
      prompt("rename table #{old_name} to") do |new_name|
        next if new_name.empty?

        mutate("renamed #{old_name} to #{new_name}") do
          Table.named(old_name).rename(new_name)
          @table = new_name if table == old_name
        end
      end
    end

    def edit_value
      entry = current_item
      return unless entry

      prompt('value', default: entry.value) { |value| mutate { entry.update(value:) } }
    end

    def delete_targets
      chosen = targets
      return if chosen.empty?

      prompt("delete #{chosen.length} entries? (y/n)") do |answer|
        next unless answer == 'y'

        mutate("deleted #{chosen.length}") do
          chosen.each do |entry|
            Tag.where(taggable_type: 'RegistryEntry', taggable_id: entry.id.to_s).delete
            entry.destroy
          end
          marked.clear
        end
      end
    end

    def tag_targets
      chosen = targets
      return if chosen.empty?

      prompt('tags', complete: { '' => -> { Completions.tags } }) do |text|
        removals, additions = text.split.partition { |token| token.start_with?('-') }
        mutate("tagged #{chosen.length}") do
          chosen.each do |entry|
            entry.tag(*additions) unless additions.empty?
            entry.untag(*removals.map { |token| token.delete_prefix('-') }) unless removals.empty?
          end
        end
      end
    end

    def move_targets
      chosen = targets
      return if chosen.empty?

      prompt('move to table', complete: { '' => -> { Completions.tables } }) do |table_name|
        next if table_name.empty?

        mutate("moved #{chosen.length} to #{table_name}") do
          chosen.each { |entry| entry.update(resource_type: table_name) }
        end
      end
    end

    def mutate(success = nil)
      yield
      self.message = success if success
    rescue Hiiro::Error => e
      self.message = e.message
    rescue Sequel::UniqueConstraintViolation
      self.message = 'already exists'
    ensure
      reload!
    end
  end
end
