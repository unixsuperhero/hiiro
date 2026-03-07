class Hiiro
  # High-level actions with side effects for task operations.
  # Each method implements a user-facing command.
  module TaskActions
    module_function

    def switch(tm, h, task_name, app_name)
      if task_name.nil?
        selected = tm.select_task_interactive
        return unless selected

        if selected.is_a?(Hash)
          if selected[:type] == :session
            h.start_tmux_session(selected[:name])
            puts "Switched to session '#{selected[:name]}'"
            return
          else
            task_name = selected[:name]
          end
        else
          task_name = selected
        end
      end

      task = tm.task_by_name(task_name)

      unless task
        session = tm.environment.find_session(task_name)
        if session
          h.start_tmux_session(session.name)
          puts "Switched to session '#{session.name}'"
          return
        end
      end

      tm.switch_to_task(task, app_name: app_name)
    end

    def stop(tm, h, task_name)
      if task_name.nil?
        task_name = tm.select_task_interactive
        return unless task_name
      end
      task = tm.task_by_name(task_name)
      tm.stop_task(task)
    end

    def app(tm, h, app_name)
      if app_name.nil?
        names = tm.environment.all_apps.map(&:name)
        app_name = h.fuzzyfind(names)
        return unless app_name
      end
      tm.open_app(app_name)
    end

    def current(tm)
      task = tm.current_task
      return STDERR.puts("Not in a task") unless task
      print task.name
    end

    def cbranch(tm)
      task = tm.current_task
      return STDERR.puts("Not in a task") unless task
      branch = task.branch(tm.environment)
      print branch if branch
    end

    def ctree(tm)
      task = tm.current_task
      return STDERR.puts("Not in a task") unless task
      print task.tree_name if task.tree_name
    end

    def csession(tm)
      task = tm.current_task
      return STDERR.puts("Not in a task") unless task
      print task.session_name if task.session_name
    end

    def todo(tm, parent_hiiro, args)
      TodoActions.handle(tm, parent_hiiro, args)
    end

    def queue(tm, parent_hiiro, h)
      task = tm.current_task
      task_info = task ? { task_name: task.name, tree_name: task.tree_name, session_name: task.session_name } : nil

      q = Hiiro::Queue.current(parent_hiiro)
      Hiiro::Queue.build_hiiro(h, q, task_info: task_info).run
    end

    def service(tm, h)
      sm = Hiiro::ServiceManager.new
      Hiiro::ServiceManager.build_hiiro(h, sm, task_manager: tm).run
    end

    def run(parent_hiiro, h)
      rt = Hiiro::RunnerTool.new
      Hiiro::RunnerTool.build_hiiro(h, rt, git: parent_hiiro.git).run
    end

    def file(tm, h)
      af = Hiiro::AppFiles.new
      Hiiro::AppFiles.build_hiiro(h, af, environment: tm.environment).run
    end
  end

  # Handles todo subcommand actions.
  module TodoActions
    module_function

    def handle(tm, parent_hiiro, args)
      todo_manager = Hiiro::TodoManager.new
      task = tm.current_task
      task_info = build_task_info(task, tm.environment)

      subcmd = args.shift
      case subcmd
      when 'ls', 'list', nil then list(todo_manager, task, args)
      when 'add' then add(todo_manager, task_info, args)
      when 'rm', 'remove' then remove(todo_manager, tm, args)
      when 'start' then start(todo_manager, tm, args)
      when 'done' then done(todo_manager, tm, args)
      when 'skip' then skip(todo_manager, tm, args)
      when 'search' then search(todo_manager, args)
      else puts "Usage: h #{tm.scope} todo <ls|add|rm|start|done|skip|search> [args]"
      end
    end

    def build_task_info(task, environment)
      return nil unless task
      { task_name: task.name, tree: task.tree_name, branch: task.branch(environment), session: task.session_name }
    end

    def list(todo_manager, task, args)
      show_all = args.delete('-a') || args.delete('--all')
      items = if show_all
        todo_manager.all
      elsif task
        todo_manager.filter_by_task(task.name).select { |i| %w[not_started started].include?(i.status) }
      else
        todo_manager.active
      end

      if items.empty?
        puts task ? "No todo items for task '#{task.name}'." : "No todo items found."
      else
        puts todo_manager.list(items)
      end
    end

    def add(todo_manager, task_info, args)
      if args.empty?
        new_items = todo_manager.edit_items(task_info: task_info)
        if new_items.empty?
          puts "No items added."
          return
        end
        todo_manager.add_items(new_items)
        if new_items.length == 1
          puts "Added: #{todo_manager.format_item(new_items.first)}"
        else
          puts "Added #{new_items.length} items:"
          new_items.each { |item| puts "  #{todo_manager.format_item(item)}" }
        end
        return
      end

      tags, text = parse_add_args(args)
      item = todo_manager.add(text, tags: tags, task_info: task_info)
      puts "Added: #{todo_manager.format_item(item)}"
    end

    def parse_add_args(args)
      tags = nil
      text_parts = []
      while args.any?
        arg = args.shift
        case arg
        when '-t', '--tags'
          tags = args.shift
        else
          text_parts << arg
        end
      end
      [tags, text_parts.join(' ')]
    end

    def remove(todo_manager, tm, args)
      id_or_index = args.shift
      unless id_or_index
        puts "Usage: h #{tm.scope} todo rm <id|index>"
        return
      end
      item = todo_manager.remove(id_or_index)
      puts item ? "Removed: #{item.text}" : "Item not found: #{id_or_index}"
    end

    def start(todo_manager, tm, args)
      id_or_index = args.shift
      unless id_or_index
        puts "Usage: h #{tm.scope} todo start <id|index>"
        return
      end
      item = todo_manager.start(id_or_index)
      puts item ? "Started: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"
    end

    def done(todo_manager, tm, args)
      id_or_index = args.shift
      unless id_or_index
        puts "Usage: h #{tm.scope} todo done <id|index>"
        return
      end
      item = todo_manager.done(id_or_index)
      puts item ? "Done: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"
    end

    def skip(todo_manager, tm, args)
      id_or_index = args.shift
      unless id_or_index
        puts "Usage: h #{tm.scope} todo skip <id|index>"
        return
      end
      item = todo_manager.skip(id_or_index)
      puts item ? "Skipped: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"
    end

    def search(todo_manager, args)
      query = args.join(' ')
      if query.empty?
        puts "Usage: h todo search <query>"
        return
      end
      items = todo_manager.search(query)
      puts items.empty? ? "No items matching: #{query}" : todo_manager.list(items)
    end
  end
end
