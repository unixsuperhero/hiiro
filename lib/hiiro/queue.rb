require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'
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

    def list_lines(all: false, statuses: nil)
      filter = statuses && Array(statuses).map(&:to_s).reject(&:empty?)
      active_statuses = filter&.any? ? STATUSES.select { |s| filter.include?(s) } : STATUSES
      lines = []
      active_statuses.each do |status|
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
            if meta['tmux_pane']
              line += "  [pane #{meta['tmux_pane']}]"
            elsif meta['tmux_session']
              line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]"
            end
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
      launch_in_mode(name, mode: :window)
    end

    def launch_in_pane(name, split:)
      launch_in_mode(name, mode: split)
    end

    private

    def launch_in_mode(name, mode:)
      dirs = queue_dirs
      md_file = File.join(dirs[:pending], "#{name}.md")
      return unless File.exist?(md_file)

      running_md = File.join(dirs[:running], "#{name}.md")
      FileUtils.mv(md_file, running_md)

      prompt_obj = Prompt.from_file(running_md, hiiro: hiiro)

      # Determine target tmux session and working directory from frontmatter
      target_session = TMUX_SESSION
      working_dir = Dir.pwd
      tree_root = nil

      if prompt_obj
        if prompt_obj.task
          target_session = prompt_obj.session_name
          tree = prompt_obj.task.tree
          if tree
            working_dir = tree.path
            tree_root = tree.path
          end
        elsif prompt_obj.session
          target_session = prompt_obj.session.name
          working_dir = prompt_obj.session.path || working_dir
        end

        if prompt_obj.tree
          working_dir = prompt_obj.tree.path
          tree_root = prompt_obj.tree.path
        end

        # Resolve app + dir frontmatter on top of whatever tree root we have
        if prompt_obj.app_name
          env = Environment.current rescue nil
          app = env&.find_app(prompt_obj.app_name)
          if app
            root = tree_root || git_root_of(working_dir)
            app_dir = File.join(root, app.relative_path)
            working_dir = prompt_obj.rel_dir ? File.join(app_dir, prompt_obj.rel_dir) : app_dir
          else
            warn "hq: app '#{prompt_obj.app_name}' not found — falling back to tree/session dir"
          end
        elsif prompt_obj.rel_dir
          working_dir = File.join(tree_root || working_dir, prompt_obj.rel_dir)
        end
      end

      # Write a clean prompt file (no frontmatter) for claude
      raw = File.read(running_md).strip
      prompt_body = prompt_obj ? strip_frontmatter(prompt_obj.doc.content.strip) : strip_frontmatter(raw)
      prompt_file = File.join(dirs[:running], "#{name}.prompt")
      File.write(prompt_file, prompt_body + "\n")

      # Write a launcher script
      fire_mode   = prompt_obj&.ignore?
      claude_cmd  = fire_mode ? 'claude -p' : 'claude'
      shell_line  = fire_mode ? '' : "exec #{Shellwords.shellescape(ENV['SHELL'] || 'zsh')}"
      script_path = File.join(dirs[:running], "#{name}.sh")
      File.write(script_path, <<~SH)
        #!/usr/bin/env bash

        cd #{Shellwords.shellescape(working_dir)}
        cat #{Shellwords.shellescape(prompt_file)} | #{claude_cmd}
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

        #{shell_line}
      SH
      FileUtils.chmod(0755, script_path)

      # Build base meta (no tmux_window/pane yet)
      meta = {
        'started_at' => Time.now.iso8601,
        'working_dir' => working_dir,
      }
      if prompt_obj
        meta['task_name']    = prompt_obj.task_name    if prompt_obj.task_name
        meta['tree_name']    = prompt_obj.tree_name    if prompt_obj.tree_name
        meta['session_name'] = prompt_obj.session_name if prompt_obj.session_name
      end

      case mode
      when :window
        # Ensure the target session exists
        unless system('tmux', 'has-session', '-t', target_session, out: File::NULL, err: File::NULL)
          system('tmux', 'new-session', '-d', '-s', target_session, '-c', working_dir)
        end
        win_name = short_window_name(name)
        system('tmux', 'new-window', '-d', '-t', target_session, '-n', win_name, '-c', working_dir, script_path)
        meta['tmux_session'] = target_session
        meta['tmux_window']  = win_name
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        puts "Launched: #{name} [#{target_session}:#{win_name}]"

      when :current
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        exec(script_path)

      when :hsplit, :vsplit
        flag = mode == :hsplit ? '-v' : '-h'
        pane_id = `tmux split-window #{flag} -P -F '\#{pane_id}' -c #{Shellwords.shellescape(working_dir)} #{Shellwords.shellescape(script_path)} 2>/dev/null`.strip
        meta['tmux_pane'] = pane_id unless pane_id.empty?
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        puts "Launched: #{name} [pane #{pane_id}]"
      end
    end

    public

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

    def select_task_or_session(hiiro)
      mapping = {}

      env = Environment.current rescue nil
      if env
        env.all_tasks.sort_by(&:name).each do |task|
          line = format("task     %-25s  tree: %s", task.name, task.tree_name || '(none)')
          mapping[line] = { type: :task, task: task }
        end
      end

      sessions = Hiiro::Tmux::Sessions.fetch rescue nil
      if sessions
        sessions.names.sort.each do |name|
          mapping[format("session  %s", name)] = { type: :session, name: name }
        end
      end

      return nil if mapping.empty?

      hiiro.fuzzyfind_from_map(mapping)
    end

    def resolve_task_info(opts, hiiro, default_task_info)
      if opts.find
        selection = select_task_or_session(hiiro)
        if selection
          case selection[:type]
          when :task    then task_info_for(selection[:task].name)
          when :session then { session_name: selection[:name] }
          end
        else
          default_task_info
        end
      elsif opts.task.is_a?(String)
        task_info_for(opts.task)
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

    # Given a (possibly-edited) prompt file and a base directory (task root),
    # return the resolved working directory accounting for app: and dir: frontmatter.
    def resolve_pane_dir(prompt_path, base_dir = Dir.pwd)
      prompt_obj = Prompt.from_file(prompt_path.to_s, hiiro: @hiiro)
      return base_dir unless prompt_obj

      tree_root   = base_dir
      working_dir = base_dir

      if prompt_obj.app_name
        env = Environment.current rescue nil
        app = env&.find_app(prompt_obj.app_name)
        if app
          app_dir     = File.join(tree_root, app.relative_path)
          working_dir = prompt_obj.rel_dir ? File.join(app_dir, prompt_obj.rel_dir) : app_dir
        elsif prompt_obj.rel_dir
          working_dir = File.join(tree_root, prompt_obj.rel_dir)
        end
      elsif prompt_obj.rel_dir
        working_dir = File.join(tree_root, prompt_obj.rel_dir)
      end

      Dir.exist?(working_dir) ? working_dir : base_dir
    rescue
      base_dir
    end

    def git_root_of(dir)
      root = `git -C #{Shellwords.shellescape(dir)} rev-parse --show-toplevel 2>/dev/null`.strip
      root.empty? ? dir : root
    end

    def slugify(text)
      text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
    end

    def add_with_frontmatter(content, task_info: nil, ignore: false, name: nil)
      queue_dirs # ensure dirs exist

      if (task_info || ignore) && !content.start_with?("---")
        fm = {}
        fm['task_name'] = task_info[:task_name] if task_info&.dig(:task_name)
        fm['tree_name'] = task_info[:tree_name] if task_info&.dig(:tree_name)
        fm['session_name'] = task_info[:session_name] if task_info&.dig(:session_name)
        fm['ignore'] = true if ignore

        if fm.any?
          content = "---\n#{fm.map { |k, v| "#{k}: #{v}" }.join("\n")}\n---\n#{content}"
        end
      end

      if name && !name.empty?
        name = slugify(name)
      else
        content_lines = content.lines.drop_while { |l| l.strip.empty? || l.start_with?('---') || l.match?(/^\w+:/) || l.start_with?('# ') }.first.to_s.strip
        name = slugify(content_lines)
      end

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
            flag(:all,    short: :a, desc: 'Show all tasks without limit; use pager if output exceeds terminal height')
            option(:status, short: :s, desc: "Filter by status (#{Queue::STATUSES.join(', ')}); repeat for multiple", multi: true)
          end
          lines = q.list_lines(all: opts.all, statuses: opts.status)
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
              if meta['tmux_pane']
                line += "  [pane #{meta['tmux_pane']}]"
              elsif meta['tmux_session']
                line += "  [#{meta['tmux_session']}:#{meta['tmux_window']}]"
              end
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

        do_add = lambda do |args, split: nil|
          q.queue_dirs
          opts = Hiiro::Options.parse(args) do
            option(:task,        short: :t, desc: 'Task name', flag_ifs: [:find])
            option(:name,        short: :n, desc: 'Base filename for the queue task')
            flag(:find,          short: :f, desc: 'Choose task/session interactively (fuzzyfind)')
            flag(:horizontal,    short: :h, desc: 'Split horizontally in the current tmux window')
            flag(:vertical,      short: :v, desc: 'Split vertically in the current tmux window')
            flag(:session,       short: :s, desc: 'Use current tmux session')
            flag(:ignore,        short: :i, desc: 'Background task — close window when done, no shell')
          end

          if opts.help?
            puts opts.help_text
            exit 1
          end

          split ||= :hsplit if opts.horizontal
          split ||= :vsplit if opts.vertical

          args = opts.args
          ti = q.resolve_task_info(opts, h, task_info)

          if opts.session
            session_name = h.tmux_client.current_session&.name
            ti = (ti || {}).merge(session_name: session_name) if session_name
          end

          # Split+interactive: open editor AND run claude in a new tmux pane
          if split && args.empty? && $stdin.tty?
            fm_lines = ["---"]
            fm_lines << "task_name: #{ti[:task_name]}" if ti&.dig(:task_name)
            fm_lines << "tree_name: #{ti[:tree_name]}" if ti&.dig(:tree_name)
            fm_lines << "session_name: #{ti[:session_name]}" if ti&.dig(:session_name)
            fm_lines << "ignore: true" if opts.ignore
            fm_lines << "# app: <partial-app-name>  (run claude from this app's directory)"
            fm_lines << "# dir: <relative-path>     (subdir within app or tree root)"
            fm_lines << "---"
            fm_lines << ""

            tmp_dir = File.join(Dir.home, '.config/hiiro/tmp')
            FileUtils.mkdir_p(tmp_dir)
            base        = File.join(tmp_dir, "hq-#{Time.now.strftime('%Y%m%d%H%M%S%L')}")
            prompt_path = "#{base}.md"
            script_path = "#{base}.sh"
            File.write(prompt_path, fm_lines.join("\n"))

            # Resolve working dir and chdir so the new pane inherits it
            task_base_dir = nil
            if ti
              if ti[:tree_name]
                env = Environment.current rescue nil
                if env
                  tree = env.find_tree(ti[:tree_name])
                  task_base_dir = tree&.path || File.join(Hiiro::WORK_DIR, ti[:tree_name])
                  task_base_dir = nil unless task_base_dir && Dir.exist?(task_base_dir)
                end
              elsif ti[:session_name]
                # Session selected (no task) — use active pane's CWD from that session
                pane_path = `tmux display-message -t #{Shellwords.shellescape(ti[:session_name])}: -p '\#{pane_current_path}' 2>/dev/null`.strip
                task_base_dir = pane_path unless pane_path.empty? || !Dir.exist?(pane_path)
              end
            end
            Dir.chdir(task_base_dir) if task_base_dir

            orig_pane  = `tmux display-message -p '\#{pane_id}'`.strip
            split_flag = split == :hsplit ? '-v' : '-h'
            claude_cmd = opts.ignore ? 'claude -p' : 'claude'
            shell_line = opts.ignore ? '' : "exec ${SHELL:-zsh}"

            File.write(script_path, <<~SH)
              #!/usr/bin/env bash
              _PROMPT=#{Shellwords.shellescape(prompt_path)}
              _BASE_DIR="$(pwd)"
              ${EDITOR:-vim} "$_PROMPT"
              tmux select-pane -t #{Shellwords.shellescape(orig_pane)}
              if [ -s "$_PROMPT" ]; then
                _WD="$(h queue pane-dir "$_PROMPT" "$_BASE_DIR" 2>/dev/null)"
                [ -n "$_WD" ] && [ -d "$_WD" ] && cd "$_WD"
                cat "$_PROMPT" | #{claude_cmd}
              fi
              rm -f #{Shellwords.shellescape(prompt_path)} #{Shellwords.shellescape(script_path)}
              #{shell_line}
            SH
            FileUtils.chmod(0755, script_path)

            new_pane = `tmux split-window #{split_flag} -P -F '\#{pane_id}' #{Shellwords.shellescape(script_path)} 2>/dev/null`.strip
            system('tmux', 'select-pane', '-t', new_pane) unless new_pane.empty?
            next
          end

          if args.empty? && !$stdin.tty?
            content = $stdin.read.strip
          elsif args.any?
            content = args.join(' ')
          else
            fm_lines = ["---"]
            fm_lines << "task_name: #{ti[:task_name]}" if ti&.dig(:task_name)
            fm_lines << "tree_name: #{ti[:tree_name]}" if ti&.dig(:tree_name)
            fm_lines << "session_name: #{ti[:session_name]}" if ti&.dig(:session_name)
            fm_lines << "ignore: true" if opts.ignore
            fm_lines << "# app: <partial-app-name>  (run claude from this app's directory)"
            fm_lines << "# dir: <relative-path>     (subdir within app or tree root)"
            fm_lines << "---"
            fm_lines << ""
            fm_content = fm_lines.join("\n")

            input = InputFile.md_file(hiiro: h, content: fm_content, append: !!fm_content, prefix: 'hq-')
            input.edit
            content = input.contents
            input.cleanup
            if content.empty?
              puts "Aborted (empty file)"
              next
            end
          end

          result = q.add_with_frontmatter(content, task_info: ti, ignore: opts.ignore, name: opts.name)
          unless result
            puts "Could not generate a task name"
            next
          end

          if split
            q.launch_in_pane(result[:name], split: split)
          else
            puts "Created: #{result[:path]}"
          end
        end

        h.add_subcmd(:add)  { |*args| do_add.call(args) }
        h.add_subcmd(:cadd) { |*args| do_add.call(args, split: :current) }
        h.add_subcmd(:hadd) { |*args| do_add.call(args, split: :hsplit) }
        h.add_subcmd(:vadd) { |*args| do_add.call(args, split: :vsplit) }

        h.add_subcmd(:wip) { |*args|
          q.queue_dirs
          opts = Hiiro::Options.parse(args) do
            option(:task,    short: :t, desc: 'Task name', flag_ifs: [:find])
            flag(:find,      short: :f, desc: 'Choose task/session interactively (fuzzyfind)')
            flag(:session,   short: :s, desc: 'Use current tmux session')
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
            fm_lines = ["---"]
            fm_lines << "task_name: #{ti[:task_name]}" if ti&.dig(:task_name)
            fm_lines << "tree_name: #{ti[:tree_name]}" if ti&.dig(:tree_name)
            fm_lines << "session_name: #{ti[:session_name]}" if ti&.dig(:session_name)
            fm_lines << "# app: <partial-app-name>  (run claude from this app's directory)"
            fm_lines << "# dir: <relative-path>     (subdir within app or tree root)"
            fm_lines << "---"
            fm_lines << ""
            File.write(path, fm_lines.join("\n"))
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
          if meta&.key?('tmux_pane')
            system('tmux', 'kill-pane', '-t', meta['tmux_pane'])
          else
            session = meta&.[]('tmux_session') || TMUX_SESSION
            win = meta&.[]('tmux_window') || name
            system('tmux', 'kill-window', '-t', "#{session}:#{win}")
          end

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

        h.add_subcmd(:sadd) { |*args|
          exec('h', 'queue', 'add', '-s', *args)
        }

        h.add_subcmd(:tadd) { |*args|
          exec('h', 'task', 'queue', 'add', *args)
        }

        h.add_subcmd(:dir) {
          q.queue_dirs
          puts DIR
        }

        # Internal: resolve working directory for a pane-launched prompt after editing.
        # Used by the cadd/hadd/vadd shell scripts: cd $(h queue pane-dir $file $base)
        h.add_subcmd(:'pane-dir') { |prompt_path = nil, base_dir = Dir.pwd|
          print q.resolve_pane_dir(prompt_path.to_s, base_dir.to_s)
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

      attr_reader :hiiro, :doc, :frontmatter

      def initialize(doc, hiiro: nil)
        @hiiro = hiiro
        @doc = doc
        @frontmatter = doc.front_matter || {}
      end

      def ignore?
        frontmatter['ignore'] == true
      end

      def task_name
        frontmatter['task_name']
      end

      def tree_name
        frontmatter['tree_name']
      end

      def app_name
        frontmatter['app']
      end

      def rel_dir
        frontmatter['dir']
      end

      def session_name
        frontmatter['session_name'] || task&.session_name
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
