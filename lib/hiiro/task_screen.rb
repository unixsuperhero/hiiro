require 'set'
require 'stringio'

class Hiiro
  # The `t ui` TUI: tasks, subtasks, and todos as a tree with a detail pane, and
  # prompts for the edits `t` supports. Edits go through TaskRecord / TodoItem and
  # TaskScreen::Ops (TaskCli::Commands), never through a copy of their rules.
  class TaskScreen < Tui::Screen
    KEY_HINT = '[enter]open [h]close [/]search [g]scope [A]closed [x]done [t]odo [n]ext [w]ait [D]one [N]ew [u]se [s]witch [q]uit'.freeze
    CLOSED = %w[done archived].freeze
    OPEN_EXCLUDED = %w[done skip].freeze

    Node = Struct.new(:kind, :depth, :task, :todo, keyword_init: true) do
      def task? = kind != :todo
      def key = [kind, task.name, todo&.id]
    end

    # `t` operations the screen shares with the CLI. They print, so stdout is
    # captured to keep their output off the alternate screen.
    class Ops
      # include, not extend: on an extended instance Commands would sit ahead of
      # these wrappers in method lookup and they could not override create/open_workspace.
      include Hiiro::TaskCli::Commands

      def opts = nil
      def herdr_client = Hiiro::Herdr.client

      def create(name) = quietly { super }

      def open_workspace(task)
        quietly { super(task, save: true) }
        nil
      end

      private

      def quietly
        saved = $stdout
        $stdout = StringIO.new
        yield
      ensure
        $stdout = saved
      end
    end

    key :enter, :toggle_expand
    key 'l', :toggle_expand
    key 'h', :collapse_or_parent
    key 'g', :toggle_scope
    key 'A', :toggle_closed
    key 'x', :toggle_done
    key 't', :add_todo
    key 'n', :edit_next
    key 'w', :edit_waiting
    key 'D', :mark_done
    key 'N', :new_task
    key 'u', :use_task
    key 's', :switch_task

    attr_reader :scope, :current, :show_closed, :expanded, :ops

    def initialize(scope: :global, current: nil, show_closed: false, ops: Ops.new)
      @scope = current ? scope : :global
      @current = current
      @show_closed = show_closed
      @ops = ops
      @expanded = Set.new
      @expanded << current.name.split('/').first if current
      super(items: [], empty_message: 'No tasks.')
      reload!
    end

    # Reads tasks and todos from the DB, then rebuilds the rows.
    def reload!(select: nil)
      @tasks = TaskRecord.order(:name).all
      @todos = TodoItem.exclude(task_name: nil).order(:id).all.group_by(&:full_task_name)
      rebuild!(select:)
    end

    # Rebuilds rows from the loaded records, keeping the cursor on the same node.
    def rebuild!(select: nil)
      key = select || current_item&.key
      @filtered = nil
      @items = build_nodes('')
      index = key && filtered_items.index { |node| node.key == key }
      state.cursor = index if index
      move(0)
    end

    def row_text(node)
      text = node.task? ? task_text(node.task) : "[#{node.todo.status == 'done' ? 'x' : ' '}] #{node.todo.text}"
      ('  ' * node.depth) + text
    end

    def format_row(node, current, line_cols) = super(row_text(node), current, line_cols)

    def max_horizontal_offset(line_cols = nil, visible = nil)
      super(line_cols, (visible || window_items).map { |node| row_text(node) })
    end

    def header_lines
      label = scope == :task ? "task(@#{current.name})" : 'global'
      ["tasks  scope:#{label}  closed:#{show_closed ? 'shown' : 'hidden'}", KEY_HINT]
    end

    def detail_lines(node)
      node.task? ? task_detail(node.task) : todo_detail(node.todo)
    end

    def match?(node, query)
      text = node.task? ? node.task.name : node.todo.text
      text.downcase.include?(query.downcase)
    end

    private

    def task_text(task)
      marker = expanded?(task) ? '▾' : '▸'
      open = todos_for(task).count { |todo| !OPEN_EXCLUDED.include?(todo.status) }
      next_action = "next: #{task.next_action}" unless task.next_action.to_s.empty?
      ["#{marker} #{task.name}", task.task_status, (open.positive? ? "(#{open})" : nil), next_action]
        .reject { |part| part.to_s.empty? }.join('  ')
    end

    def field(label, value) = "#{label.ljust(8)} #{value.to_s.empty? ? '-' : value}"

    def task_detail(task)
      todos = todos_for(task)
      resources = task.resources.all
      [
        field('name', task.name),
        field('status', task.task_status),
        field('next', task.next_action),
        field('waiting', task.waiting_on),
        field('tree', task.tree),
        field('session', task.session),
        field('code dir', TaskLocation.for(task).code_directory),
        field('home', task.home),
        "todos (#{todos.length})",
        *todos.map { |todo| "  [#{todo.status == 'done' ? 'x' : ' '}] #{todo.text}" },
        "resources (#{resources.length})",
        *resources.map { |resource| "  #{resource.kind}  #{resource.target}" },
      ]
    end

    def todo_detail(todo)
      [
        field('task', todo.full_task_name),
        field('id', todo.id),
        field('status', todo.status),
        field('text', todo.text),
        field('tags', todo.tags),
        field('created', todo.created_at),
      ]
    end

    def todos_for(task) = @todos.fetch(task.name, [])

    def closed?(task) = CLOSED.include?(task.status)

    def shown?(task) = show_closed || !closed?(task)

    def expanded?(task)
      !state.query.empty? || @expanded.include?(task.name) || (scope == :task && task.name == current.name)
    end

    def subtasks(task)
      prefix = "#{task.name}/"
      @tasks.select { |sub| sub.name.start_with?(prefix) && !sub.name.delete_prefix(prefix).include?('/') && shown?(sub) }
    end

    def roots
      if scope == :task
        root = @tasks.find { |task| task.name == current.name }
        return root ? [root] : []
      end

      @tasks.select { |task| !task.name.include?('/') && shown?(task) }
    end

    # With a query every task counts as expanded; a row is kept when it matches
    # or when something beneath it does.
    def build_nodes(query)
      roots.flat_map { |task| task_nodes(task, 0, query) }
    end

    def task_nodes(task, depth, query)
      node = Node.new(kind: task.name.include?('/') ? :subtask : :task, depth:, task:, todo: nil)
      return [node] if query.empty? && !expanded?(task)

      todos = todos_for(task).map { |todo| Node.new(kind: :todo, depth: depth + 1, task:, todo:) }
      todos = todos.select { |todo| match?(todo, query) } unless query.empty?
      children = todos + subtasks(task).flat_map { |sub| task_nodes(sub, depth + 1, query) }
      return [] unless query.empty? || match?(node, query) || children.any?

      [node, *children]
    end

    def filtered_items
      return items if state.query.empty?
      return @filtered.last if @filtered&.first == state.query

      @filtered = [state.query, build_nodes(state.query)]
      @filtered.last
    end

    def node_task = current_item&.task

    def toggle_expand
      node = current_item
      return unless node&.task?

      name = node.task.name
      @expanded.include?(name) ? @expanded.delete(name) : @expanded.add(name)
      rebuild!
    end

    def collapse_or_parent
      node = current_item
      return unless node

      if node.task? && @expanded.include?(node.task.name)
        @expanded.delete(node.task.name)
        return rebuild!
      end

      parent = node.task? ? node.task.name.rpartition('/').first : node.task.name
      index = filtered_items.index { |row| row.task? && row.task.name == parent }
      return unless index

      state.cursor = index
      move(0)
    end

    def toggle_scope
      unless current
        self.message = 'no current task'
        return
      end

      @scope = scope == :task ? :global : :task
      rebuild!
    end

    def toggle_closed
      @show_closed = !show_closed
      rebuild!
    end

    def toggle_done
      node = current_item
      return unless node
      return add_todo unless node.todo

      todo = node.todo
      mutate do
        todo.update_status(todo.status == 'done' ? 'not_started' : 'done')
        todo.save
      end
    end

    def add_todo
      task = node_task
      return unless task

      prompt('todo', complete: { '@' => -> { Completions.projects }, '#' => -> { Completions.tags } }) do |text|
        next if text.strip.empty?

        mutate do
          item = TodoItem.create(text:, task_name: task.name)
          @expanded << task.name
          self.message = "added todo #{item.id}"
        end
      end
    end

    def edit_next
      task = node_task
      return unless task

      prompt('next action', default: task.next_action, complete: { '@' => -> { Completions.projects }, '#' => -> { Completions.tags } }) { |text| mutate { task.set_next!(text) } }
    end

    def edit_waiting
      task = node_task
      return unless task

      prompt('waiting on', default: task.waiting_on, complete: { '@' => -> { Completions.projects }, '#' => -> { Completions.tags } }) { |text| mutate { task.set_waiting!(text) } }
    end

    def mark_done
      task = node_task
      return unless task

      prompt("mark #{task.name} done? (y/n)") do |answer|
        next unless answer == 'y'

        mutate("#{task.name} done") { task.set_status!('done') }
      end
    end

    def new_task
      prompt('new task', complete: { '' => -> { Completions.tasks } }) do |name|
        next if name.strip.empty?

        select = nil
        mutate("created #{name}") do
          record = ops.create(name)
          select = [record.name.include?('/') ? :subtask : :task, record.name, nil]
        end
        rebuild!(select:) if select
      end
    end

    def use_task
      task = node_task
      return unless task

      mutate("current task: #{task.name}") { ops.save_current(task) }
    end

    def switch_task
      task = node_task
      return unless task

      ops.open_workspace(task)
      finish(true)
    rescue Hiiro::Error => e
      self.message = e.message
    end

    def mutate(success = nil)
      yield
      self.message = success if success
    rescue Hiiro::Error => e
      self.message = e.message
    ensure
      reload!
    end
  end
end
