require 'tempfile'

class Hiiro
  class Queue
    # High-level actions with side effects for queue operations.
    # Each method implements a user-facing command.
    module Actions
      module_function

      def watch(q)
        q.queue_dirs
        puts "Watching #{File.join(Queue::DIR, 'pending')} ..."
        puts "Press Ctrl-C to stop"
        loop do
          q.tasks_in(:pending).each { |name| q.launch_task(name) }
          sleep 2
        end
      end

      def run(q, name)
        if name
          name = name.sub(/\.md$/, '')
          found = q.find_task(name)
          if found.nil?
            puts "Task not found: #{name}"
            return
          end
          unless found.pending?
            puts "Task '#{name}' is #{found.status}, not pending"
            return
          end
          q.launch_task(name)
        else
          pending = q.tasks_in(:pending)
          if pending.empty?
            puts "No pending tasks"
            return
          end
          pending.each { |n| q.launch_task(n) }
        end
      end

      def list(q)
        tasks = q.all_tasks
        if tasks.empty?
          puts "No tasks"
          return
        end
        tasks.each { |t| puts Presenter.format_task_line(t, q) }
      end

      def status(q)
        tasks = q.all_tasks
        if tasks.empty?
          puts "No tasks"
          return
        end
        tasks.each { |t| puts Presenter.format_status_line(t, q) }
      end

      def attach(q, h, name)
        running = q.tasks_in(:running)
        if running.empty?
          puts "No running tasks"
          return
        end

        if name.nil?
          name = h.fuzzyfind(running)
        else
          result = Matcher.by_prefix(running, name)
          if result.one?
            name = result.first.item
          elsif result.ambiguous?
            puts "Ambiguous match for '#{name}':"
            result.matches.each { |m| puts "  #{m.item}" }
            return
          else
            puts "No running task matching: #{name}"
            return
          end
        end

        return unless name

        meta = q.meta_for(name, :running)
        session = meta&.[]('tmux_session') || Queue::TMUX_SESSION
        win = meta&.[]('tmux_window') || name
        system('tmux', 'switch-client', '-t', "#{session}:#{win}")
      end

      def session(q)
        work_dir = File.expand_path('~/work')
        unless system('tmux', 'has-session', '-t', Queue::TMUX_SESSION, out: File::NULL, err: File::NULL)
          system('tmux', 'new-session', '-d', '-s', Queue::TMUX_SESSION, '-c', work_dir)
        end
        system('tmux', 'switch-client', '-t', Queue::TMUX_SESSION)
      end

      def add(q, h, args, task_info)
        q.queue_dirs
        opts = Hiiro::Options.parse(args) do
          option(:task, short: :t, desc: 'Task name')
          flag(:choose, short: :T, desc: 'Choose task interactively')
        end
        args = opts.args
        ti = q.resolve_task_info(opts, h, task_info)

        content = read_add_content(args, ti)
        return if content.nil?

        if content.empty?
          puts "Aborted (empty file)"
          return
        end

        result = q.add_task(content, task_info: ti)
        if result
          puts "Created: #{result[:path]}"
        else
          puts "Could not generate a task name"
        end
      end

      def read_add_content(args, ti)
        if args.empty? && !$stdin.tty?
          $stdin.read.strip
        elsif args.any?
          args.join(' ')
        else
          edit_new_task(ti)
        end
      end

      def edit_new_task(ti)
        tmpfile = Tempfile.new(['hq-', '.md'])
        if ti
          fm_lines = ["---"]
          fm_lines << "task_name: #{ti[:task_name]}" if ti[:task_name]
          fm_lines << "tree_name: #{ti[:tree_name]}" if ti[:tree_name]
          fm_lines << "session_name: #{ti[:session_name]}" if ti[:session_name]
          fm_lines << "---"
          fm_lines << ""
          tmpfile.write(fm_lines.join("\n"))
        end
        tmpfile.close

        editor = ENV['EDITOR'] || 'vim'
        system(editor, tmpfile.path)
        content = File.read(tmpfile.path).strip
        tmpfile.unlink
        content
      end

      def wip(q, h, args, task_info)
        q.queue_dirs
        editor = ENV['EDITOR'] || 'vim'
        opts = Hiiro::Options.parse(args) do
          option(:task, short: :t, desc: 'Task name')
          flag(:choose, short: :T, desc: 'Choose task interactively')
        end
        args = opts.args
        ti = q.resolve_task_info(opts, h, task_info)
        name = args.first

        if name.nil?
          existing = q.tasks_in(:wip)
          if existing.any?
            name = h.fuzzyfind(existing)
            return unless name
          else
            puts "No wip tasks. Provide a name to create one."
            return
          end
        end

        name = name.sub(/\.md$/, '')
        path = File.join(q.queue_dirs[:wip], "#{name}.md")

        unless File.exist?(path)
          if ti
            fm_lines = ["---"]
            fm_lines << "task_name: #{ti[:task_name]}" if ti[:task_name]
            fm_lines << "tree_name: #{ti[:tree_name]}" if ti[:tree_name]
            fm_lines << "session_name: #{ti[:session_name]}" if ti[:session_name]
            fm_lines << "---"
            fm_lines << ""
            File.write(path, fm_lines.join("\n"))
          end
        end

        system(editor, path)
      end

      def ready(q, h, name)
        wip = q.tasks_in(:wip)
        if wip.empty?
          puts "No wip tasks"
          return
        end

        name = wip.size == 1 ? wip.first : h.fuzzyfind(wip) if name.nil?
        return unless name

        name = name.sub(/\.md$/, '')
        src = File.join(q.queue_dirs[:wip], "#{name}.md")
        unless File.exist?(src)
          puts "Wip task not found: #{name}"
          return
        end

        dst = File.join(q.queue_dirs[:pending], "#{name}.md")
        FileUtils.mv(src, dst)
        puts "Moved to pending: #{name}"
      end

      def kill(q, h, name)
        running = q.tasks_in(:running)
        if running.empty?
          puts "No running tasks"
          return
        end

        name = running.size == 1 ? running.first : h.fuzzyfind(running) if name.nil?
        return unless name

        meta = q.meta_for(name, :running)
        session = meta&.[]('tmux_session') || Queue::TMUX_SESSION
        win = meta&.[]('tmux_window') || name
        system('tmux', 'kill-window', '-t', "#{session}:#{win}")

        dirs = q.queue_dirs
        md = File.join(dirs[:running], "#{name}.md")
        meta_path = File.join(dirs[:running], "#{name}.meta")
        FileUtils.mv(md, File.join(dirs[:failed], "#{name}.md")) if File.exist?(md)
        FileUtils.mv(meta_path, File.join(dirs[:failed], "#{name}.meta")) if File.exist?(meta_path)
        puts "Killed: #{name}"
      end

      def retry_task(q, h, name)
        retryable = q.tasks_in(:failed) + q.tasks_in(:done)
        if retryable.empty?
          puts "No failed/done tasks to retry"
          return
        end

        name = retryable.size == 1 ? retryable.first : h.fuzzyfind(retryable) if name.nil?
        return unless name

        found = q.find_task(name)
        unless found && %w[failed done].include?(found.status)
          puts "Task '#{name}' is not in failed/done state"
          return
        end

        dirs = q.queue_dirs
        src_dir = dirs[found.status.to_sym]
        FileUtils.mv(File.join(src_dir, "#{name}.md"), File.join(dirs[:pending], "#{name}.md"))
        meta_path = File.join(src_dir, "#{name}.meta")
        FileUtils.rm_f(meta_path) if File.exist?(meta_path)
        puts "Moved to pending: #{name}"
      end

      def clean(q)
        dirs = q.queue_dirs
        count = 0
        %i[done failed].each do |status|
          Dir.glob(File.join(dirs[status], '*')).each do |f|
            FileUtils.rm_f(f)
            count += 1
          end
        end
        puts "Cleaned #{count} files"
      end

      def dir(q)
        q.queue_dirs
        puts Queue::DIR
      end
    end
  end
end
