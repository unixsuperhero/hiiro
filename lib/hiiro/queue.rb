require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'
require 'tempfile'

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

    # --- Data Access (Low-Level) ---

    def queue_dirs
      @queue_dirs ||= STATUSES.each_with_object({}) do |name, h|
        dir = File.join(DIR, name)
        FileUtils.mkdir_p(dir)
        h[name.to_sym] = dir
      end
    end

    def task_path(name, status)
      File.join(queue_dirs[status], "#{name}.md")
    end

    def meta_path(name, status)
      File.join(queue_dirs[status], "#{name}.meta")
    end

    def prompt_path(name)
      File.join(queue_dirs[:running], "#{name}.prompt")
    end

    def script_path(name)
      File.join(queue_dirs[:running], "#{name}.sh")
    end

    def tasks_in(status)
      dir = queue_dirs[status]
      Dir.glob(File.join(dir, '*.md')).sort.map { |f| File.basename(f, '.md') }
    end

    def all_tasks
      STATUSES.flat_map do |status|
        tasks_in(status.to_sym).map { |name| QueueTask.new(name: name, status: status, queue: self) }
      end
    end

    def find_task(name)
      STATUSES.each do |status|
        md = task_path(name, status.to_sym)
        return QueueTask.new(name: name, status: status, queue: self) if File.exist?(md)
      end
      nil
    end

    def meta_for(name, status)
      path = meta_path(name, status)
      File.exist?(path) ? YAML.safe_load_file(path) : nil
    end

    def read_prompt(filepath)
      return nil unless File.exist?(filepath)
      Prompt.from_file(filepath)
    end

    # --- Atomic Operations (Low-Level) ---

    def strip_frontmatter(text)
      lines = text.lines
      return text unless lines.first&.strip == '---'
      end_idx = lines[1..].index { |l| l.strip == '---' }
      return text unless end_idx
      lines[(end_idx + 2)..].join.strip
    end

    def slugify(text)
      text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
    end

    def short_window_name(name)
      base = name[0, 8]
      return base unless existing_window_name?(base)

      (2..99).each do |i|
        candidate = "#{base[0, 7]}#{i}"
        return candidate unless existing_window_name?(candidate)
      end
      base
    end

    def existing_window_name?(wname)
      windows = `tmux list-windows -a -F '#\\{window_name\\}' 2>/dev/null`.lines(chomp: true)
      windows.include?(wname)
    end

    def generate_task_name(content, task_info: nil)
      content_lines = content.lines.drop_while { |l| l.strip.empty? || l.start_with?('---') || l.match?(/^\w+:/) }.first.to_s.strip
      name = slugify(content_lines)

      if name.empty?
        name = Time.now.strftime("%Y%m%d%H%M%S")
        name += '-' + task_info[:task_name] if task_info&.key?(:task_name)
      end

      base_name = name
      counter = 1
      while File.exist?(File.join(DIR, 'pending', "#{name}.md"))
        counter += 1
        name = "#{base_name}-#{counter}"
      end

      name
    end

    def build_frontmatter(task_info)
      return nil unless task_info

      fm = {}
      fm['task_name'] = task_info[:task_name] if task_info[:task_name]
      fm['tree_name'] = task_info[:tree_name] if task_info[:tree_name]
      fm['session_name'] = task_info[:session_name] if task_info[:session_name]

      return nil if fm.empty?

      "---\n#{fm.map { |k, v| "#{k}: #{v}" }.join("\n")}\n---\n"
    end

    def build_content_with_frontmatter(content, task_info: nil)
      frontmatter = build_frontmatter(task_info)
      frontmatter ? "#{frontmatter}#{content}" : content
    end

    # --- Mid-Level: Task Resolution ---

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
        h[line] = task.name
      end

      hiiro.fuzzyfind_from_map(mapping)
    end

    def resolve_task_info(opts, hiiro, default_task_info)
      task_name = if opts.choose
        select_task(hiiro)
      elsif opts.task
        opts.task
      else
        nil
      end

      task_name ? task_info_for(task_name) : default_task_info
    end

    # --- High-Level: Actions with Side Effects ---

    def add_task(content, task_info: nil)
      queue_dirs # ensure dirs exist
      content = build_content_with_frontmatter(content, task_info: task_info)
      name = generate_task_name(content, task_info: task_info)
      path = File.join(DIR, 'pending', "#{name}.md")
      File.write(path, content + "\n")
      { name: name, path: path }
    end

    def move_task(name, from_status, to_status)
      src = task_path(name, from_status)
      dst = task_path(name, to_status)
      return false unless File.exist?(src)

      FileUtils.mv(src, dst)
      true
    end

    def ensure_tmux_session(session = TMUX_SESSION)
      unless system('tmux', 'has-session', '-t', session, out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', session)
      end
    end

    def launch_task(name)
      launcher = TaskLauncher.new(self, name, hiiro: hiiro)
      launcher.launch
    end

    # --- Presentation (delegated to QueuePresenter) ---

    def task_preview(name, status)
      QueuePresenter.task_preview(task_path(name, status))
    end

    # --- Legacy compatibility ---

    def add_with_frontmatter(content, task_info: nil)
      add_task(content, task_info: task_info)
    end

    # --- Hiiro Integration ---

    def self.build_hiiro(parent_hiiro, q=nil, task_info: nil)
      q ||= current(parent_hiiro)
      commands = QueueCommands.new(q, parent_hiiro, task_info: task_info)
      commands.build
    end
  end

  # Value object representing a queue task
  class QueueTask
    attr_reader :name, :status, :queue

    def initialize(name:, status:, queue:)
      @name = name
      @status = status
      @queue = queue
    end

    def path
      queue.task_path(name, status.to_sym)
    end

    def meta
      queue.meta_for(name, status.to_sym)
    end

    def pending?
      status == 'pending'
    end

    def running?
      status == 'running'
    end

    def to_h
      { name: name, status: status }
    end
  end

  # Presentation layer for queue output
  class QueuePresenter
    def self.task_preview(path)
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

    def self.format_task_line(task, queue)
      line = "%-10s %s" % [task.status, task.name]
      meta = task.meta

      if meta && task.running?
        started = meta['started_at']
        if started
          elapsed = Time.now - Time.parse(started)
          mins = (elapsed / 60).to_i
          line += "  (#{mins}m)"
        end
        line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]" if meta['tmux_session']
      end

      preview = queue.task_preview(task.name, task.status.to_sym)
      line += "  #{preview}" if preview
      line
    end

    def self.format_status_line(task, queue)
      meta = task.meta
      line = "%-10s %s" % [task.status, task.name]

      if meta
        started = meta['started_at']
        if started && task.running?
          elapsed = Time.now - Time.parse(started)
          mins = (elapsed / 60).to_i
          line += "  (#{mins}m elapsed)"
        end
        line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]" if meta['tmux_session']
        line += "  dir:#{meta['working_dir']}" if meta['working_dir']
      end
      line
    end
  end

  # Orchestrates launching a task in tmux
  class TaskLauncher
    attr_reader :queue, :name, :hiiro

    def initialize(queue, name, hiiro: nil)
      @queue = queue
      @name = name
      @hiiro = hiiro
    end

    def launch
      return false unless move_to_running
      return false unless prompt_obj = load_prompt

      target = resolve_target(prompt_obj)
      ensure_session_exists(target)
      write_files(prompt_obj, target)
      create_tmux_window(target)
      write_meta(prompt_obj, target)

      puts "Launched: #{name} [#{target[:session]}:#{target[:window_name]}]"
      true
    end

    private

    def move_to_running
      src = queue.task_path(name, :pending)
      return false unless File.exist?(src)

      dst = queue.task_path(name, :running)
      FileUtils.mv(src, dst)
      true
    end

    def load_prompt
      running_md = queue.task_path(name, :running)
      Queue::Prompt.from_file(running_md, hiiro: hiiro)
    end

    def resolve_target(prompt_obj)
      target_session = Queue::TMUX_SESSION
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

      {
        session: target_session,
        working_dir: working_dir,
        window_name: queue.short_window_name(name)
      }
    end

    def ensure_session_exists(target)
      unless system('tmux', 'has-session', '-t', target[:session], out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', target[:session], '-c', target[:working_dir])
      end
    end

    def write_files(prompt_obj, target)
      running_md = queue.task_path(name, :running)
      raw = File.read(running_md).strip
      prompt_body = prompt_obj ? prompt_obj.doc.content.strip : queue.strip_frontmatter(raw)

      # Write clean prompt file
      File.write(queue.prompt_path(name), prompt_body + "\n")

      # Write launcher script
      write_launcher_script(target)
    end

    def write_launcher_script(target)
      script_content = <<~SH
        #!/usr/bin/env bash

        cd #{Shellwords.shellescape(target[:working_dir])}
        cat #{Shellwords.shellescape(queue.prompt_path(name))} | claude
        HQ_EXIT=$?

        # Move task files to done/failed based on exit code
        ruby -e '
          require "fileutils"
          name = #{name.inspect}
          qdir = #{Queue::DIR.inspect}
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

      path = queue.script_path(name)
      File.write(path, script_content)
      FileUtils.chmod(0755, path)
    end

    def create_tmux_window(target)
      system('tmux', 'new-window', '-d', '-t', target[:session],
             '-n', target[:window_name], '-c', target[:working_dir],
             queue.script_path(name))
    end

    def write_meta(prompt_obj, target)
      meta = {
        'tmux_session' => target[:session],
        'tmux_window' => target[:window_name],
        'started_at' => Time.now.iso8601,
        'working_dir' => target[:working_dir],
      }

      if prompt_obj
        meta['task_name'] = prompt_obj.task_name if prompt_obj.task_name
        meta['tree_name'] = prompt_obj.tree_name if prompt_obj.tree_name
        meta['session_name'] = prompt_obj.session_name if prompt_obj.session_name
      end

      File.write(queue.meta_path(name, :running), meta.to_yaml)
    end
  end

  # Handles building the Hiiro command interface
  class QueueCommands
    attr_reader :queue, :parent_hiiro, :task_info

    def initialize(queue, parent_hiiro, task_info: nil)
      @queue = queue
      @parent_hiiro = parent_hiiro
      @task_info = task_info
    end

    def build
      q = queue
      ti = task_info

      parent_hiiro.make_child do |h|
        h.add_subcmd(:watch) { QueueActions.watch(q) }
        h.add_subcmd(:run) { |name = nil| QueueActions.run(q, name) }
        h.add_subcmd(:ls) { QueueActions.list(q) }
        h.add_subcmd(:list) { QueueActions.list(q) }
        h.add_subcmd(:status) { QueueActions.status(q) }

        h.add_subcmd(:attach) { |name = nil| QueueActions.attach(q, h, name) }
        h.add_subcmd(:session) { QueueActions.session(q) }

        h.add_subcmd(:add) { |*args| QueueActions.add(q, h, args, ti) }
        h.add_subcmd(:wip) { |*args| QueueActions.wip(q, h, args, ti) }
        h.add_subcmd(:ready) { |name = nil| QueueActions.ready(q, h, name) }

        h.add_subcmd(:kill) { |name = nil| QueueActions.kill(q, h, name) }
        h.add_subcmd(:retry) { |name = nil| QueueActions.retry_task(q, h, name) }
        h.add_subcmd(:clean) { QueueActions.clean(q) }
        h.add_subcmd(:dir) { QueueActions.dir(q) }
      end
    end
  end

  # High-level actions with side effects
  module QueueActions
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
      tasks.each { |t| puts QueuePresenter.format_task_line(t, q) }
    end

    def status(q)
      tasks = q.all_tasks
      if tasks.empty?
        puts "No tasks"
        return
      end
      tasks.each { |t| puts QueuePresenter.format_status_line(t, q) }
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

  class Queue
    # Prompt parsing (data object)
    class Prompt
      def self.from_file(path, hiiro: nil)
        return unless File.exist?(path)
        new(FrontMatterParser::Parser.parse_file(path), hiiro: hiiro)
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
