require_relative 'task_manager'

class Hiiro
  module Tasks
    def self.build_hiiro(parent_hiiro, tm)
      task_hiiro = parent_hiiro.make_child do |h|
        h.add_subcmd(:list) { tm.list }
        h.add_subcmd(:ls) { tm.list }

        h.add_subcmd(:start) do |task_name, app_name=nil|
          tm.start_task(task_name, app_name: app_name)
        end

        h.add_subcmd(:switch) do |task_name=nil, app_name=nil|
          if task_name.nil?
            selected = tm.select_task_interactive
            next unless selected

            if selected.is_a?(Hash)
              if selected[:type] == :session
                h.start_tmux_session(selected[:name])
                puts "Switched to session '#{selected[:name]}'"
                next
              else
                task_name = selected[:name]
              end
            else
              task_name = selected
            end
          end

          task = tm.task_by_name(task_name)

          # If no task found, check for a matching tmux session
          unless task
            session = tm.environment.find_session(task_name)
            if session
              h.start_tmux_session(session.name)
              puts "Switched to session '#{session.name}'"
              next
            end
          end

          tm.switch_to_task(task, app_name: app_name)
        end

        h.add_subcmd(:app) do |app_name=nil|
          if app_name.nil?
            names = tm.environment.all_apps.map(&:name)
            app_name = h.fuzzyfind(names)
            next unless app_name
          end
          tm.open_app(app_name)
        end

        h.add_subcmd(:apps) { tm.list_apps }

        h.add_subcmd(:cd) do |app_name=nil|
          tm.cd_to_app(app_name)
        end

        h.add_subcmd(:path) do |app_name=nil|
          tm.app_path(app_name)
        end

        h.add_subcmd(:branch) do |task_name=nil|
          print tm.value_for_task(task_name, &:branch)
        end

        h.add_subcmd(:tree) do |task_name=nil|
          print tm.value_for_task(task_name, &:tree_name)
        end

        h.add_subcmd(:session) do |task_name=nil|
          print tm.value_for_task(task_name, &:session_name)
        end

        h.add_subcmd(:current) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.name
        end

        h.add_subcmd(:cbranch) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.branch if task.branch
        end

        h.add_subcmd(:ctree) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.tree_name if task.tree_name
        end

        h.add_subcmd(:csession) do
          task = tm.current_task
          next STDERR.puts("Not in a task") unless task
          print task.session_name if task.session_name
        end

        h.add_subcmd(:status) { tm.status }
        h.add_subcmd(:st) { tm.status }

        h.add_subcmd(:save) { tm.save }

        h.add_subcmd(:stop) do |task_name=nil|
          if task_name.nil?
            task_name = tm.select_task_interactive
            next unless task_name
          end
          task = tm.task_by_name(task_name)
          tm.stop_task(task)
        end

        h.add_subcmd(:edit) do
          system(ENV['EDITOR'] || 'nvim', __FILE__)
        end

        h.add_subcmd(:todo) do |*todo_args|
          todo_manager = Hiiro::TodoManager.new
          task = tm.current_task

          task_info = if task
            {
              task_name: task.name,
              tree: task.tree_name,
              branch: task.branch,
              session: task.session_name
            }
          end

          todo_subcmd = todo_args.shift
          case todo_subcmd
          when 'ls', 'list', nil
            show_all = todo_args.delete('-a') || todo_args.delete('--all')
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

          when 'add'
            if todo_args.empty?
              new_items = todo_manager.edit_items(task_info: task_info)
              if new_items.empty?
                puts "No items added."
                next
              end
              todo_manager.add_items(new_items)
              if new_items.length == 1
                puts "Added: #{todo_manager.format_item(new_items.first)}"
              else
                puts "Added #{new_items.length} items:"
                new_items.each { |item| puts "  #{todo_manager.format_item(item)}" }
              end
              next
            end

            tags = nil
            text_parts = []
            while todo_args.any?
              arg = todo_args.shift
              case arg
              when '-t', '--tags'
                tags = todo_args.shift
              else
                text_parts << arg
              end
            end
            text = text_parts.join(' ')
            item = todo_manager.add(text, tags: tags, task_info: task_info)
            puts "Added: #{todo_manager.format_item(item)}"

          when 'rm', 'remove'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo rm <id|index>"
              next
            end
            item = todo_manager.remove(id_or_index)
            puts item ? "Removed: #{item.text}" : "Item not found: #{id_or_index}"

          when 'start'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo start <id|index>"
              next
            end
            item = todo_manager.start(id_or_index)
            puts item ? "Started: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'done'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo done <id|index>"
              next
            end
            item = todo_manager.done(id_or_index)
            puts item ? "Done: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'skip'
            id_or_index = todo_args.shift
            unless id_or_index
              puts "Usage: h #{tm.scope} todo skip <id|index>"
              next
            end
            item = todo_manager.skip(id_or_index)
            puts item ? "Skipped: #{todo_manager.format_item(item)}" : "Item not found: #{id_or_index}"

          when 'search'
            query = todo_args.join(' ')
            if query.empty?
              puts "Usage: h #{tm.scope} todo search <query>"
              next
            end
            items = todo_manager.search(query)
            if items.empty?
              puts "No items matching: #{query}"
            else
              puts todo_manager.list(items)
            end

          else
            puts "Usage: h #{tm.scope} todo <ls|add|rm|start|done|skip|search> [args]"
          end
        end

        h.add_subcmd(:queue) do |*queue_args|
          task = tm.current_task
          task_info = if task
            {
              task_name: task.name,
              tree_name: task.tree_name,
              session_name: task.session_name
            }
          end

          q = Hiiro::Queue.current(parent_hiiro)
          Hiiro::Queue.build_hiiro(h, q, task_info: task_info).run
        end

        h.add_subcmd(:service) do |*svc_args|
          sm = Hiiro::ServiceManager.new
          Hiiro::ServiceManager.build_hiiro(h, sm, task_manager: tm).run
        end

        h.add_subcmd(:run) do |*run_args|
          rt = Hiiro::RunnerTool.new
          Hiiro::RunnerTool.build_hiiro(h, rt, git: parent_hiiro.git).run
        end

        h.add_subcmd(:file) do |*file_args|
          af = Hiiro::AppFiles.new
          Hiiro::AppFiles.build_hiiro(h, af, environment: tm.environment).run
        end
      end

      task_hiiro
    end
  end
end
