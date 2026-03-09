require_relative 'task_manager'

class Hiiro
  module Tasks
    def self.build_hiiro(parent_hiiro, tm)
      task_hiiro = parent_hiiro.make_child do |h|
        h.add_subcmd(:list) do
          items = tm.tasks
          if items.empty?
            puts tm.scope == :subtask ? "No subtasks found" : "No tasks found"
            puts "Use 'h #{tm.scope} start NAME' to create one."
            next
          end

          current = tm.current_task
          puts "#{tm.list_label}:"
          puts

          items.each do |task|
            marker = (current && current.name == task.name) ? "*" : " "
            line = task.display_line(scope: tm.scope, environment: tm.environment)
            puts "#{marker} #{line}"

            if tm.scope == :task
              tm.subtasks(task).each do |st|
                sub_marker = (current && current.name == st.name) ? "*" : " "
                sub_line = st.display_line(scope: :subtask, environment: tm.environment)
                puts "#{sub_marker} - #{sub_line}"
              end
            end
          end

          available = tm.available_trees
          if available.any?
            puts
            available.each do |tree|
              branch_str = tree.branch ? "  [#{tree.branch}]" : tree.detached? ? "  [(detached)]" : ""
              puts format("  %-25s  (available)%s", tree.name, branch_str)
            end
          end
        end

        h.add_subcmd(:ls) do |*args|
          h.run_subcmd(:list, *args)
        end

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

        h.add_subcmd(:apps) do
          apps = tm.all_apps
          if apps.any?
            puts "Configured apps:"
            puts
            apps.each do |app|
              puts format("  %-20s => %s", app.name, app.relative_path)
            end
          else
            puts "No apps configured."
            puts "Create #{Hiiro::TaskManager::APPS_FILE} with format:"
            puts "  app_name: relative/path/from/repo"
          end
        end

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

        h.add_subcmd(:status) do
          info = tm.status_info
          unless info
            puts "Not currently in a task session"
            next
          end

          puts "Task: #{info[:name]}"
          puts "Worktree: #{info[:tree_name]}"
          puts "Path: #{info[:path] || '(unknown)'}"
          puts "Session: #{info[:session_name]}"
          puts "Parent: #{info[:parent_name]}" if info[:parent_name]
        end

        h.add_subcmd(:st) do |*args|
          h.run_subcmd(:status, *args)
        end

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
          task = tm.current_task
          task_info = if task
            {
              task_name: task.name,
              tree: task.tree_name,
              branch: task.branch,
              session: task.session_name
            }
          end

          todo_manager = Hiiro::TodoManager.new
          Hiiro::TodoManager.build_hiiro(h, todo_manager, task_info: task_info).run
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
