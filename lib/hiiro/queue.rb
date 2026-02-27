require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'

class Hiiro
  class Queue
    DIR = File.join(Dir.home, '.config/hiiro/queue')
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

    def all_tasks
      STATUSES.flat_map do |status|
        tasks_in(status.to_sym).map { |name| { name: name, status: status } }
      end
    end

    def meta_for(name, status)
      path = File.join(queue_dirs[status], "#{name}.meta")
      File.exist?(path) ? YAML.safe_load_file(path) : nil
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
      prompt_text = File.read(running_md).strip

      # Determine target tmux session and working directory from frontmatter
      target_session = TMUX_SESSION
      working_dir = Dir.pwd

      if prompt_obj
        if prompt_obj.task
          target_session = prompt_obj.task.session_name
          tree = prompt_obj.task.tree
          working_dir = tree.path if tree
        elsif prompt_obj.session
          target_session = prompt_obj.session.name
        end

        if prompt_obj.tree
          working_dir = prompt_obj.tree.path
        end
      end

      # Ensure the target session exists
      unless system('tmux', 'has-session', '-t', target_session, out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', target_session, '-c', working_dir)
      end

      # Build the cleanup script that runs after claude exits
      cleanup_ruby = [
        'ruby', '-e',
        'require "fileutils"; ' \
        "name=#{name.inspect}; qdir=#{DIR.inspect}; " \
        'exit_code = ENV["HQ_EXIT"].to_i; ' \
        'src=File.join(qdir,"running",name+".md"); ' \
        'dst_dir = exit_code == 0 ? "done" : "failed"; ' \
        'FileUtils.mv(src, File.join(qdir, dst_dir, name+".md")) if File.exist?(src); ' \
        'meta=File.join(qdir,"running",name+".meta"); ' \
        'FileUtils.mv(meta, File.join(qdir, dst_dir, name+".meta")) if File.exist?(meta)'
      ].shelljoin

      # Run claude interactively in tmux window, then cleanup on exit
      shell_cmd = "cd #{Shellwords.shellescape(working_dir)} && claude #{Shellwords.shellescape(prompt_text)}; HQ_EXIT=$?; #{cleanup_ruby}; exec #{ENV['SHELL'] || 'zsh'}"

      system('tmux', 'new-window', '-t', target_session, '-n', name, '-c', working_dir, shell_cmd)

      # Write meta sidecar
      meta = {
        'tmux_session' => target_session,
        'tmux_window' => name,
        'started_at' => Time.now.iso8601,
        'working_dir' => working_dir,
      }
      if prompt_obj
        meta['task_name'] = prompt_obj.task_name if prompt_obj.task_name
        meta['tree_name'] = prompt_obj.tree_name if prompt_obj.tree_name
        meta['session_name'] = prompt_obj.session_name if prompt_obj.session_name
      end
      File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)

      puts "Launched: #{name} [#{target_session}]"
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

      name = slugify(content.lines.reject { |l| l.start_with?('---') || l.match?(/^\w+:/) }.first.to_s.strip)
      return nil if name.empty?

      base_name = name
      counter = 1
      while File.exist?(File.join(DIR, 'pending', "#{name}.md"))
        counter += 1
        name = "#{base_name}-#{counter}"
      end

      path = File.join(DIR, 'pending', "#{name}.md")
      File.write(path, content + "\n")
      { name: name, path: path }
    end

    def self.build_hiiro(parent_hiiro, q=nil, task_info: nil)
      q ||= current(parent_hiiro)

      parent_hiiro.make_child(parent_hiiro.subcmd || '', *parent_hiiro.args) do |h|
        h.add_subcmd(:watch) {
          q.queue_dirs
          puts "Watching #{File.join(DIR, 'pending')} ..."
          puts "Press Ctrl-C to stop"
          loop do
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

        h.add_subcmd(:ls) {
          tasks = q.all_tasks
          if tasks.empty?
            puts "No tasks"
            next
          end
          tasks.each do |t|
            puts "%-10s %s" % [t[:status], t[:name]]
          end
        }

        h.add_subcmd(:list) {
          tasks = q.all_tasks
          if tasks.empty?
            puts "No tasks"
            next
          end
          tasks.each do |t|
            puts "%-10s %s" % [t[:status], t[:name]]
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
            name = running.size == 1 ? running.first : h.fuzzyfind(running)
          end

          if name
            meta = q.meta_for(name, :running)
            session = meta&.[]('tmux_session') || TMUX_SESSION
            exec('tmux', 'select-window', '-t', "#{session}:#{name}")
          end
        }

        h.add_subcmd(:add) { |*args|
          q.queue_dirs

          if args.empty? && !$stdin.tty?
            content = $stdin.read.strip
          elsif args.any?
            content = args.join(' ')
          else
            require 'tempfile'
            tmpfile = Tempfile.new(['hq-', '.md'])

            # Pre-fill with frontmatter template if task_info is available
            if task_info
              fm_lines = ["---"]
              fm_lines << "task_name: #{task_info[:task_name]}" if task_info[:task_name]
              fm_lines << "tree_name: #{task_info[:tree_name]}" if task_info[:tree_name]
              fm_lines << "session_name: #{task_info[:session_name]}" if task_info[:session_name]
              fm_lines << "---"
              fm_lines << ""
              tmpfile.write(fm_lines.join("\n"))
            end

            tmpfile.close
            editor = ENV['EDITOR'] || 'vim'
            system(editor, tmpfile.path)
            content = File.read(tmpfile.path).strip
            tmpfile.unlink
            if content.empty?
              puts "Aborted (empty file)"
              next
            end
          end

          result = q.add_with_frontmatter(content, task_info: task_info)
          if result
            puts "Created: #{result[:path]}"
          else
            puts "Could not generate a task name"
          end
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
          system('tmux', 'kill-window', '-t', "#{session}:#{name}")

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
          FileUtils.mv(File.join(src_dir, "#{name}.md"), File.join(dirs[:pending], "#{name}.md"))
          meta_path = File.join(src_dir, "#{name}.meta")
          FileUtils.rm_f(meta_path) if File.exist?(meta_path)
          puts "Moved to pending: #{name}"
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
      end
    end

    class Prompt
      def self.from_file(path, hiiro: nil)
        return unless File.exist?(path)

        new(FrontMatterParser::Parser.parse_file(path), hiiro:)
      end

      attr_reader :hiiro, :doc, :frontmatter, :prompt
      attr_reader :task_name, :tree_name, :session_name

      def initialize(doc, hiiro: nil)
        @hiiro = hiiro
        @doc = doc
        @frontmatter = doc.front_matter
        @prompt = prompt

        @task_name = doc.front_matter['task_name']
        @tree_name = doc.front_matter['tree_name']
        @session_name = doc.front_matter['session_name']
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
