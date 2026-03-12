require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'
require 'tempfile'

class Hiiro
  class Queue
    DIR = Hiiro::Config.data_path('queue')
    TMUX_SESSION = 'hq'
    STATUSES = %w[wip pending running done failed].freeze

    def self.current(hiiro=nil)
      @current ||= new(hiiro)
    end

    attr_reader :hiiro

    def initialize(hiiro=nil)
      @hiiro = hiiro
    end

    def read_prompt(filepath)
      return false unless File.exist?(filepath)

      Prompt.from_file(filepath)
    end

    def queue_dirs
      @queue_dirs ||= STATUSES.each_with_object({}) do |name, h|
        dir = File.join(DIR, name)
        FileUtils.mkdir_p(dir)
        h[name.to_sym] = dir
      end
    end

    def tasks_in(status)
      dir = queue_dirs[status]
      Dir.glob(File.join(dir, '*.md')).sort.map { |f| File.basename(f, '.md') }
    end

    def tasks_in_sorted(status)
      dir = queue_dirs[status]
      Dir.glob(File.join(dir, '*.md')).map { |f|
        { name: File.basename(f, '.md'), mtime: File.mtime(f) }
      }.sort_by { |t| -t[:mtime].to_i }
    end

    def format_mtime(mtime)
      now = Time.now
      mtime.year == now.year ? mtime.strftime("%m-%d %H:%M") : mtime.strftime("%Y-%m-%d %H:%M")
    end

    def list_lines(all: false)
      lines = []
      STATUSES.each do |status|
        tasks = tasks_in_sorted(status.to_sym)
        next if tasks.empty?

        display = all ? tasks : tasks.first(10)
        display.each do |t|
          ts = format_mtime(t[:mtime])
          line = "%-10s %-12s %s" % [status, ts, t[:name]]
          meta = meta_for(t[:name], status.to_sym)
          if meta && status == 'running'
            started = meta['started_at']
            if started
              elapsed = Time.now - Time.parse(started)
              mins = (elapsed / 60).to_i
              line += "  (#{mins}m)"
            end
            line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]" if meta['tmux_session']
          end
          preview = task_preview(t[:name], status.to_sym)
          line += "  #{preview}" if preview
          lines << line
        end

        if !all && tasks.size > 10
          lines << "  ... and #{tasks.size - 10} more"
        end
      end
      lines
    end

    def all_tasks
      STATUSES.flat_map do |status|
        tasks_in(status.to_sym).map { |name| { name: name, status: status } }
      end
    end

    def meta_for(name, status)
      path = File.join(queue_dirs[status], "#{name}.meta")
      File.exist?(path) ? YAML.safe_load_file(path) : nil
    end

    def task_preview(name, status)
      path = File.join(queue_dirs[status], "#{name}.md")
      return nil unless File.exist?(path)

      lines = File.readlines(path, chomp: true)
      # Skip frontmatter
      if lines.first == '---'
        end_idx = lines[1..].index('---')
        lines = lines[(end_idx + 2)..] if end_idx
      end
      first = lines&.find { |l| !l.strip.empty? }&.strip
      return nil unless first

      first.length > 60 ? "| #{first[0, 57]}..." : "| #{first}"
    end

    def find_task(name)
      STATUSES.each do |status|
        md = File.join(queue_dirs[status.to_sym], "#{name}.md")
        return { name: name, status: status } if File.exist?(md)
      end
      nil
    end

    def ensure_tmux_session
      unless system('tmux', 'has-session', '-t', TMUX_SESSION, out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', TMUX_SESSION)
      end
    end

    def launch_task(name)
      dirs = queue_dirs
      md_file = File.join(dirs[:pending], "#{name}.md")
      return unless File.exist?(md_file)

      running_md = File.join(dirs[:running], "#{name}.md")
      FileUtils.mv(md_file, running_md)

      prompt_obj = Prompt.from_file(running_md, hiiro: hiiro)

      # Determine target tmux session and working directory from frontmatter
      target_session = TMUX_SESSION
      working_dir = Dir.pwd

      if prompt_obj
        if prompt_obj.task
          target_session = prompt_obj.session_name
          tree = prompt_obj.task.tree
          working_dir = tree.path if tree
        elsif prompt_obj.session
          target_session = prompt_obj.session.name
          working_dir = prompt_obj.session.path || working_dir
        end

        if prompt_obj.tree
          working_dir = prompt_obj.tree.path
        end
      end

      # Ensure the target session exists
      unless system('tmux', 'has-session', '-t', target_session, out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', target_session, '-c', working_dir)
      end

      # Write a clean prompt file (no frontmatter) for claude
      raw = File.read(running_md).strip
      prompt_body = prompt_obj ? strip_frontmatter(prompt_obj.doc.content.strip) : strip_frontmatter(raw)
      prompt_file = File.join(dirs[:running], "#{name}.prompt")
      File.write(prompt_file, prompt_body + "\n")

      # Write a launcher script
      script_path = File.join(dirs[:running], "#{name}.sh")
      File.write(script_path, <<~SH)
        #!/usr/bin/env bash

        cd #{Shellwords.shellescape(working_dir)}
        cat #{Shellwords.shellescape(prompt_file)} | claude
        HQ_EXIT=$?

        # Move task files to done/failed based on exit code
        ruby -e '
          require "fileutils"
          name = #{name.inspect}
          qdir = #{DIR.inspect}
          exit_code = ENV["HQ_EXIT"].to_i
          dst_dir = exit_code == 0 ? "done" : "failed"
          %w[.md .meta .prompt .sh].each do |ext|
            src = File.join(qdir, "running", name + ext)
            if ext == ".prompt" || ext == ".sh"
              FileUtils.rm_f(src)
            elsif File.exist?(src)
              FileUtils.mv(src, File.join(qdir, dst_dir, name + ext))
            end
          end
        '

        exec #{Shellwords.shellescape(ENV['SHELL'] || 'zsh')}
      SH
      FileUtils.chmod(0755, script_path)

      win_name = short_window_name(name)
      system('tmux', 'new-window', '-d', '-t', target_session, '-n', win_name, '-c', working_dir, script_path)

      # Write meta sidecar
      meta = {
        'tmux_session' => target_session,
        'tmux_window' => win_name,
        'started_at' => Time.now.iso8601,
        'working_dir' => working_dir,
      }
      if prompt_obj
        meta['task_name'] = prompt_obj.task_name if prompt_obj.task_name
        meta['tree_name'] = prompt_obj.tree_name if prompt_obj.tree_name
        meta['session_name'] = prompt_obj.session_name if prompt_obj.session_name
      end
      File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)

      puts "Launched: #{name} [#{target_session}:#{win_name}]"
    end

    def task_info_for(task_name)
      env = Environment.current rescue nil
      return nil unless env

      task = env.find_task(task_name)
      return nil unless task

      {
        task_name: task.name,
        tree_name: task.tree_name,
        session_name: task.session_name,
      }
    end

    def select_task(hiiro)
      env = Environment.current rescue nil
      return nil unless env

      tasks = env.all_tasks.sort_by(&:name)
      return nil if tasks.empty?

      mapping = tasks.each_with_object({}) do |task, h|
        line = format("%-25s  tree: %-20s", task.name, task.tree_name || '(none)')
        h[line] = task
      end

      hiiro.fuzzyfind_from_map(mapping)
    end

    def resolve_task_info(opts, hiiro, default_task_info)
      task_name = if opts.choose
        select_task(hiiro)&.name
      elsif opts.task
        opts.task
      else
        nil
      end

      if task_name
        task_info_for(task_name)
      else
        default_task_info
      end
    end

    def strip_frontmatter(text)
      lines = text.lines
      return text unless lines.first&.strip == '---'
      end_idx = lines[1..].index { |l| l.strip == '---' }
      return text unless end_idx
      lines[(end_idx + 2)..].join.strip
    end

    def short_window_name(name)
      base = name[0, 8]
      return base unless existing_window_name?(base)

      # append digits to make unique
      (2..99).each do |i|
        candidate = "#{base[0, 7]}#{i}"
        return candidate unless existing_window_name?(candidate)
      end
      base
    end

    def existing_window_name?(wname)
      windows = `tmux list-windows -a -F '#\{window_name\}' 2>/dev/null`.lines(chomp: true)
      windows.include?(wname)
    end

    def slugify(text)
      text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
    end

    def add_with_frontmatter(content, task_info: nil)
      queue_dirs # ensure dirs exist

      if task_info
        fm = {}
        fm['task_name'] = task_info[:task_name] if task_info[:task_name]
        fm['tree_name'] = task_info[:tree_name] if task_info[:tree_name]
        fm['session_name'] = task_info[:session_name] if task_info[:session_name]

        if fm.any?
          content = "---\n#{fm.map { |k, v| "#{k}: #{v}" }.join("\n")}\n---\n#{content}"
        end
      end

      content_lines =content.lines.drop_while { |l| l.strip.empty? || l.start_with?('---') || l.match?(/^\w+:/) }.first.to_s.strip
      name = slugify(content_lines)

      if name.empty?
        name = Time.now.strftime("%Y%m%d%H%M%S")
        name += '-' + task_info[:task_name] if task_info&.key?(:task_name)
      end

      path, name = Hiiro::Paths.unique_path(queue_dirs[:pending], name)
      File.write(path, content + "\n")
      { name: name, path: path }
    end

    def self.build_hiiro(parent_hiiro, q=nil, task_info: nil)
      q ||= current(parent_hiiro)

      parent_hiiro.make_child do |h|
        h.add_subcmd(:watch) {
          q.queue_dirs
          current_version = `gem which hiiro`.sub(/.*hiiro-/, '').sub(/\/.*/, '')
          puts "Watching #{File.join(DIR, 'pending')} ..."
          puts "Press Ctrl-C to stop"
          loops = 0
          loop do
            loops += 1
            if current_version
              latest = `gem which hiiro`.sub(/.*hiiro-/, '').sub(/\/.*/, '') rescue nil

              if latest && latest != current_version
                puts "New hiiro version detected (#{latest}), restarting..."
                exec('h', 'queue', 'watch')
              end
            end
            q.tasks_in(:pending).each { |name| q.launch_task(name) }
            sleep 2
          end
        }

        h.add_subcmd(:run) { |name = nil|
          if name
            name = name.sub(/\.md$/, '')
            found = q.find_task(name)
            if found.nil?
              puts "Task not found: #{name}"
              next
            end
            if found[:status] != 'pending'
              puts "Task '#{name}' is #{found[:status]}, not pending"
              next
            end
            q.launch_task(name)
          else
            pending = q.tasks_in(:pending)
            if pending.empty?
              puts "No pending tasks"
              next
            end
            pending.each { |n| q.launch_task(n) }
          end
        }

        h.add_subcmd(:ls, :list) { |*args|
          opts = Hiiro::Options.parse(args) do
            flag(:all, short: :a, desc: 'Show all tasks without limit; use pager if output exceeds terminal height')
          end
          lines = q.list_lines(all: opts.all)
          if lines.empty?
            puts "No tasks"
            next
          end
          if opts.all
            terminal_lines = ENV['LINES']&.to_i || 24
            if lines.size > terminal_lines
              IO.popen(ENV['PAGER'] || 'less', 'w') { |io| io.puts lines }
            else
              puts lines
            end
          else
            puts lines
          end
        }

        h.add_subcmd(:status) {
          tasks = q.all_tasks
          if tasks.empty?
            puts "No tasks"
            next
          end
          tasks.each do |t|
            meta = q.meta_for(t[:name], t[:status].to_sym)
            line = "%-10s %s" % [t[:status], t[:name]]
            if meta
              started = meta['started_at']
              if started && t[:status] == 'running'
                elapsed = Time.now - Time.parse(started)
                mins = (elapsed / 60).to_i
                line += "  (#{mins}m elapsed)"
              end
              line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]" if meta['tmux_session']
              line += "  dir:#{meta['working_dir']}" if meta['working_dir']
            end
            puts line
          end
        }

        h.add_subcmd(:attach) { |name = nil|
          running = q.tasks_in(:running)
          if running.empty?
            puts "No running tasks"
            next
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
              next
            else
              puts "No running task matching: #{name}"
              next
            end
          end

          next unless name

          meta = q.meta_for(name, :running)
          session = meta&.[]('tmux_session') || TMUX_SESSION
          win = meta&.[]('tmux_window') || name
          system('tmux', 'switch-client', '-t', "#{session}:#{win}")
        }

        h.add_subcmd(:session) {
          work_dir = File.expand_path('~/work')
          Tmux.open_session(TMUX_SESSION, start_directory: work_dir)
        }

        h.add_subcmd(:add) { |*args|
          q.queue_dirs
          opts = Hiiro::Options.parse(args) do
            option(:task, short: :t, desc: 'Task name')
            flag(:choose, short: :T, desc: 'Choose task interactively')
            flag(:session, short: :s, desc: 'Use current tmux session')
          end

          if opts.help?
            puts opts.help_text
            exit 1
          end

          args = opts.args
          ti = q.resolve_task_info(opts, h, task_info)

          if opts.session
            session_name = h.tmux_client.current_session&.name
            ti = (ti || {}).merge(session_name: session_name) if session_name
          end

          tmpfile = Tempfile.new(['hq-', '.md'])
          prompt_file = tmpfile.path
          if args.empty? && !$stdin.tty?
            content = $stdin.read.strip
          elsif args.any?
            content = args.join(' ')
          else
            # Pre-fill with frontmatter template if task_info is available
            if ti
              fm_lines = ["---"]
              fm_lines << "task_name: #{ti[:task_name]}" if ti[:task_name]
              fm_lines << "tree_name: #{ti[:tree_name]}" if ti[:tree_name]
              fm_lines << "session_name: #{ti[:session_name]}" if ti[:session_name]
              fm_lines << "---"
              fm_lines << "\n"
              tmpfile.write(fm_lines.join("\n"))
            end

            tmpfile.close
            if h.vim?
              system(h.editor, '+$', tmpfile.path)
            else
              system(h.editor, tmpfile.path)
            end
            content = File.read(tmpfile.path).strip
            tmpfile.unlink
            if content.empty?
              puts "Aborted (empty file)"
              next
            end
          end

          result = q.add_with_frontmatter(content, task_info: ti)
          if result
            puts "Created: #{result[:path]}"
          else
            puts "Could not generate a task name"
          end
        }

        h.add_subcmd(:wip) { |*args|
          q.queue_dirs
          opts = Hiiro::Options.parse(args) do
            option(:task, short: :t, desc: 'Task name')
            flag(:choose, short: :T, desc: 'Choose task interactively')
            flag(:session, short: :s, desc: 'Use current tmux session')
          end
          args = opts.args
          ti = q.resolve_task_info(opts, h, task_info)

          if opts.session
            session_name = h.tmux_client.current_session&.name
            ti = (ti || {}).merge(session_name: session_name) if session_name
          end

          name = args.first

          if name.nil?
            existing = q.tasks_in(:wip)
            if existing.any?
              name = h.fuzzyfind(existing)
              next unless name
            else
              puts "No wip tasks. Provide a name to create one."
              next
            end
          end

          name = name.sub(/\.md$/, '')
          path = File.join(q.queue_dirs[:wip], "#{name}.md")

          unless File.exist?(path)
            # Pre-fill with frontmatter if task_info available
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

          h.edit_files(path)
        }

        h.add_subcmd(:ready) { |name = nil|
          wip = q.tasks_in(:wip)
          if wip.empty?
            puts "No wip tasks"
            next
          end

          if name.nil?
            name = wip.size == 1 ? wip.first : h.fuzzyfind(wip)
          end

          next unless name

          name = name.sub(/\.md$/, '')
          src = File.join(q.queue_dirs[:wip], "#{name}.md")
          unless File.exist?(src)
            puts "Wip task not found: #{name}"
            next
          end

          dst, dest_name = Hiiro::Paths.unique_path(q.queue_dirs[:pending], name)
          if dest_name != name
            FileUtils.mv(src, File.join(q.queue_dirs[:wip], "#{dest_name}.md"))
            src = File.join(q.queue_dirs[:wip], "#{dest_name}.md")
          end
          FileUtils.mv(src, dst)
          puts "Moved to pending: #{dest_name}"
        }

        h.add_subcmd(:kill) { |name = nil|
          running = q.tasks_in(:running)
          if running.empty?
            puts "No running tasks"
            next
          end

          if name.nil?
            name = running.size == 1 ? running.first : h.fuzzyfind(running)
          end

          next unless name

          meta = q.meta_for(name, :running)
          session = meta&.[]('tmux_session') || TMUX_SESSION
          win = meta&.[]('tmux_window') || name
          system('tmux', 'kill-window', '-t', "#{session}:#{win}")

          dirs = q.queue_dirs
          md = File.join(dirs[:running], "#{name}.md")
          meta_path = File.join(dirs[:running], "#{name}.meta")
          FileUtils.mv(md, File.join(dirs[:failed], "#{name}.md")) if File.exist?(md)
          FileUtils.mv(meta_path, File.join(dirs[:failed], "#{name}.meta")) if File.exist?(meta_path)
          puts "Killed: #{name}"
        }

        h.add_subcmd(:retry) { |name = nil|
          retryable = q.tasks_in(:failed) + q.tasks_in(:done)
          if retryable.empty?
            puts "No failed/done tasks to retry"
            next
          end

          if name.nil?
            name = retryable.size == 1 ? retryable.first : h.fuzzyfind(retryable)
          end

          next unless name

          found = q.find_task(name)
          unless found && %w[failed done].include?(found[:status])
            puts "Task '#{name}' is not in failed/done state"
            next
          end

          dirs = q.queue_dirs
          src_dir = dirs[found[:status].to_sym]
          dst, dest_name = Hiiro::Paths.unique_path(dirs[:pending], name)
          FileUtils.mv(File.join(src_dir, "#{name}.md"), dst)
          meta_path = File.join(src_dir, "#{name}.meta")
          FileUtils.rm_f(meta_path) if File.exist?(meta_path)
          puts "Moved to pending: #{dest_name}"
        }

        h.add_subcmd(:clean) {
          dirs = q.queue_dirs
          count = 0
          %i[done failed].each do |status|
            Dir.glob(File.join(dirs[status], '*')).each do |f|
              FileUtils.rm_f(f)
              count += 1
            end
          end
          puts "Cleaned #{count} files"
        }

        h.add_subcmd(:dir) {
          q.queue_dirs
          puts DIR
        }

        h.add_subcmd(:migrate) {
          old_dir = File.join(Dir.home, '.config/hiiro/queue')
          new_dir = DIR

          unless Dir.exist?(old_dir)
            puts "Nothing to migrate: #{old_dir} does not exist"
            next
          end

          if old_dir == new_dir
            puts "Source and destination are the same: #{old_dir}"
            next
          end

          if Dir.exist?(new_dir) && Dir.glob(File.join(new_dir, '**', '*')).any?
            puts "Destination already has files: #{new_dir}"
            puts "Remove it manually if you want to migrate from #{old_dir}"
            next
          end

          FileUtils.mkdir_p(File.dirname(new_dir))
          FileUtils.mv(old_dir, new_dir)
          puts "Migrated: #{old_dir} -> #{new_dir}"
        }
      end
    end

    class Prompt
      def self.from_file(path, hiiro: nil)
        return unless File.exist?(path)

        new(FrontMatterParser::Parser.parse_file(path), hiiro:)
      end

      attr_reader :hiiro, :doc, :frontmatter, :prompt

      def initialize(doc, hiiro: nil)
        @hiiro = hiiro
        @doc = doc
        @frontmatter = doc.front_matter
        @prompt = prompt
      end

      def task_name
        doc.front_matter['task_name']
      end

      def tree_name
        doc.front_matter['tree_name']
      end

      def session_name
        doc.front_matter['session_name'] || task&.session_name
      end

      def task
        return nil unless task_name
        hiiro&.environment&.find_task(task_name)
      end

      def session
        return nil unless session_name
        hiiro&.environment&.find_session(session_name)
      end

      def tree
        return nil unless tree_name
        hiiro&.environment&.find_tree(tree_name)
      end
    end
  end
end
