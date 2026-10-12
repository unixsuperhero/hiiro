require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'
class Hiiro
  class Queue
    DIR = Hiiro::Config.data_path('queue')
    HERDR_WORKSPACE = 'hq'
    STATUSES = %w[wip pending running done failed].freeze

    def self.current(hiiro=nil, context: nil)
      new(hiiro, context: context)
    end

    attr_reader :hiiro

    def initialize(hiiro=nil, context: nil)
      @hiiro = hiiro
      @context = context
    end

    def read_prompt(filepath)
      return false unless File.exist?(filepath)

      Prompt.from_file(filepath, hiiro: hiiro)
    end

    def queue_dirs
      @queue_dirs ||= STATUSES.each_with_object({}) do |name, h|
        dir = File.join(DIR, name)
        FileUtils.mkdir_p(dir)
        h[name.to_sym] = dir
      end
    end

    def entries_in(status)
      Entry.in(queue_dirs, status.to_sym)
    end

    def tasks_in(status)
      entries_in(status).map(&:name)
    end

    def tasks_in_sorted(status)
      entries_in(status).map { |e| { name: e.name, mtime: e.modified_at } }.sort_by { |t| -t[:mtime].to_i }
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
          run = entry_for(t[:name], status.to_sym).execution
          if run
            line += "  (#{run.elapsed_minutes}m)" if run.started_at
            line += "  [pane #{run.location.pane_id}]" if run.location.pane?
            line += "  [tab #{run.location.tab_id}]" if !run.location.pane? && run.location.tab?
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
      STATUSES.flat_map { |status| entries_in(status).map(&:to_h) }
    end

    def entry_for(name, status)
      Entry.new(dirs: queue_dirs, name: name, status: status.to_sym)
    end

    def meta_for(name, status)
      entry_for(name, status).meta
    end

    def task_preview(name, status)
      entry_for(name, status).preview
    end

    def find_task(name)
      Entry.find(queue_dirs, name)&.to_h
    end

    def ensure_herdr_workspace(name = HERDR_WORKSPACE, cwd: nil)
      herdr.find_workspace(name) || herdr.new_workspace(name, start_directory: cwd, focus: false)
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
      prompt_obj = Prompt.from_file(md_file, hiiro: hiiro)
      location = resolve_prompt_context(prompt_obj)
      working_dir = location.start_directory
      target_workspace = workspace_for_prompt(prompt_obj, location)
      calling_pane = calling_pane!(location) if %i[hsplit vsplit].include?(mode)

      FileUtils.mv(md_file, running_md)

      # Write a clean prompt file (no frontmatter) for the agent
      raw = File.read(running_md).strip
      prompt_body = prompt_obj ? strip_frontmatter(prompt_obj.doc.content.strip) : strip_frontmatter(raw)
      prompt_file = File.join(dirs[:running], "#{name}.prompt")
      File.write(prompt_file, prompt_body + "\n")

      # Write a launcher script
      fire_mode   = prompt_obj&.ignore?
      agent_cmd   = fire_mode ? 'omp -p' : 'omp'
      shell_line  = fire_mode ? '' : "exec #{Shellwords.shellescape(ENV['SHELL'] || 'zsh')}"
      script_path = File.join(dirs[:running], "#{name}.sh")
      File.write(script_path, <<~SH)
        #!/usr/bin/env bash

        cd #{Shellwords.shellescape(working_dir)} || exit $?
        #{agent_cmd} @#{Shellwords.shellescape(prompt_file)}
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

      # Build base metadata; Herdr IDs are added after the tab/pane is created.
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
        workspace = ensure_herdr_workspace(target_workspace, cwd: working_dir)
        tab_name = short_window_name(name)
        created = Hiiro::Herdr::TabCreation.create(
          herdr,
          name: tab_name,
          workspace: workspace,
          start_directory: working_dir,
          command: script_path,
          focus: false
        )
        meta.merge!(created.location(workspace_id: workspace.id).to_meta)
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        puts "Launched: #{name} [#{meta['herdr_tab'] || workspace.id}]"

      when :current
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        exec(script_path)

      when :hsplit, :vsplit
        direction = mode == :hsplit ? :down : :right
        pane = herdr.split_pane(
          target: calling_pane,
          direction: direction,
          start_directory: working_dir,
          command: script_path,
          focus: true
        )
        meta['herdr_workspace'] = pane&.workspace_id
        meta['herdr_tab'] = pane&.tab_id
        meta['herdr_pane'] = pane&.id
        File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)
        puts "Launched: #{name} [pane #{pane&.id}]"
      end
    end

    public

    def context
      @context ||= hiiro ? hiiro.context : CurrentTask.new(herdr: -> { herdr }, pin: false).context
    end

    def chooser
      hiiro && ->(mapping) { hiiro.fuzzyfind_from_map(mapping) }
    end

    def task_info_for(task_name)
      task = CurrentTask.new(task: task_name, pin: false, chooser: chooser).resolve!
      { task_name: task.name }
    end

    def select_task_or_session(hiiro)
      mapping = TaskRecord.all_as_list.to_h { |task| ["task     #{task.name}", { type: :task, task: task }] }
      herdr.workspaces.each do |workspace|
        mapping["workspace #{workspace.name}"] = { type: :session, name: workspace.name }
      end
      hiiro.fuzzyfind_from_map(mapping) unless mapping.empty?
    end

    def resolve_task_info(opts, hiiro, default_task_info)
      if opts.find
        selection = select_task_or_session(hiiro)
        raise Error, "Selection cancelled" unless selection

        selection[:type] == :task ? task_info_for(selection[:task].name) : { session_name: selection[:name] }
      elsif opts.task.is_a?(String)
        matches = TaskRecord.all_as_list.select { |task| task.name.start_with?(opts.task) }
        matches.empty? ? session_info_for(opts.task) : task_info_for(opts.task)
      else
        default_task_info || (context.task && { task_name: context.task.name })
      end
    end

    def select_workspace(ref)
      workspaces = herdr.workspaces.to_a
      workspace = workspaces.find { |item| item.id == ref } ||
        CurrentTask.select(workspaces, ref, kind: "workspace", chooser: chooser)
      workspace || raise(Error, "Workspace not found: #{ref}")
    end

    def session_info_for(prefix)
      { session_name: select_workspace(prefix).name }
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
      herdr.tabs(all: true).names.include?(wname)
    end

    def directory_for_workspace(ref, terminal: context.terminal)
      workspace = select_workspace(ref)
      path = workspace.path
      if !path || path.empty?
        terminal.validate!(herdr)
        pane = herdr.get_pane(terminal.pane_id) if terminal.pane?
        path = pane.foreground_cwd || pane.cwd if pane && pane.workspace_id == workspace.id
      end
      raise Error, "Workspace has no usable directory: #{workspace.name}" unless path && Dir.exist?(path)

      File.realpath(path)
    end

    def herdr
      hiiro&.herdr_client || Hiiro::Herdr.client
    end

    def calling_pane!(location = context)
      terminal = location.terminal
      terminal.validate!(herdr)
      raise Error, "An explicit calling Herdr pane is required" unless terminal.pane?

      terminal.pane_id
    end

    def calling_workspace_name
      terminal = context.terminal.validate!(herdr)
      workspace = herdr.get_workspace(terminal.workspace_id) if terminal.workspace_id
      raise Error, "An explicit calling Herdr workspace is required" unless workspace

      workspace.name
    end

    def resolve_prompt_context(prompt, base_dir: nil)
      raise Error, "Prompt file not found" unless prompt
      location = if prompt.task_name && @context&.task&.name == prompt.task_name
        @context
      elsif prompt.task_name
        CurrentTask.new(task: prompt.task_name, cwd: base_dir || @context&.invocation_directory || Dir.pwd,
          herdr: -> { herdr }, pin: false, chooser: chooser).context
      else
        context
      end
      root = nil
      if prompt.tree_name
        tree = Environment.new(path: location.invocation_directory).find_tree(prompt.tree_name, chooser: chooser)
        raise Error, "Tree not found: #{prompt.tree_name}" unless tree
        root = tree.path
      end
      if prompt.session_name
        workspace = select_workspace(prompt.session_name)
        root ||= directory_for_workspace(workspace.id, terminal: location.terminal) unless location.task
      end
      root ||= base_dir if base_dir && !location.task
      if root
        location = TaskLocation.for(location.task, root: root, root_source: :frontmatter,
          invocation_directory: location.invocation_directory, terminal: location.terminal,
          task_source: location.task_source, project: location.project, app: location.app)
      end
      if prompt.app_name
        app = Environment.new(path: location.invocation_directory).find_app(prompt.app_name, chooser: chooser)
        raise Error, "App not found: #{prompt.app_name}" unless app
        location = location.for_app(app)
      end
      if prompt.rel_dir
        raise Error, "Queue directory cannot be blank" if prompt.rel_dir.to_s.strip.empty?
        directory = File.expand_path(prompt.rel_dir, location.start_directory)
        location = location.with_directory(directory, source: :frontmatter)
        raise Error, "Queue directory escapes its root: #{directory}" unless TaskLocation.contains?(location.root_directory, directory)
      end
      location.validate!
      location
    end

    def workspace_for_prompt(prompt, location)
      return select_workspace(prompt.session_name).name if prompt.session_name
      location.task ? location.workspace_label : HERDR_WORKSPACE
    end

    def resolve_pane_dir(prompt_path, base_dir = nil)
      resolve_prompt_context(Prompt.from_file(prompt_path.to_s, hiiro: hiiro), base_dir: base_dir).start_directory
    end

    def slugify(text)
      text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
    end

    def add_with_frontmatter(content, task_info: nil, ignore: false, name: nil)
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
      resolve_prompt_context(Prompt.new(FrontMatterParser::Parser.new(:md).call(content)))

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

    def self.hiiro_version
      `gem which hiiro`.sub(/.*hiiro-/, '').sub(/\/.*/, '').strip
    end

    def self.build_hiiro(parent_hiiro, q=nil, task_info: nil, context: nil, args: parent_hiiro.args)
      q ||= current(parent_hiiro, context: context)

      parent_hiiro.make_child(context: context || -> { q.context }, args: args) do |h|
        h.add_subcmd(:watch) {
          q.queue_dirs
          current_version = hiiro_version
          puts "Watching #{File.join(DIR, 'pending')} (v#{current_version}) ..."
          puts "Press Ctrl-C to stop"
          loops = 0
          loop do
            loops += 1
            if current_version
              latest = hiiro_version rescue nil

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
          statuses = Array(opts.status)
          opts.args.each do |arg|
            matched = Queue::STATUSES.select { |s| s.start_with?(arg) }
            if matched.empty?
              puts "Unknown status: '#{arg}' (valid: #{Queue::STATUSES.join(', ')})"
              next
            end
            statuses.concat(matched)
          end
          lines = q.list_lines(all: opts.all, statuses: statuses.uniq)
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
            entry = q.entry_for(t[:name], t[:status])
            meta = entry.meta
            line = "%-10s %s" % [t[:status], t[:name]]
            if meta
              run = entry.execution
              line += "  (#{run.elapsed_minutes}m elapsed)" if run&.started_at
              loc = Hiiro::Herdr::Location.from_meta(meta)
              line += "  [pane #{loc.pane_id}]" if loc.pane?
              line += "  [tab #{loc.tab_id}]" if !loc.pane? && loc.tab?
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
          if meta&.[]('herdr_tab')
            h.herdr_client.focus_tab(meta['herdr_tab'])
          elsif meta&.[]('herdr_workspace')
            h.herdr_client.focus_workspace(meta['herdr_workspace'])
          else
            puts "No Herdr location recorded for '#{name}'"
          end
        }

        h.add_subcmd(:peek) { |name = nil|
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
          pane_id = meta&.[]('herdr_pane')
          unless pane_id
            puts "No Herdr pane recorded for '#{name}'"
            next
          end

          text = h.herdr_client.read_pane(pane_id)
          if text.nil? || text.empty?
            puts "(pane empty or unreadable)"
          else
            puts text
          end
        }

        h.add_subcmd(:say) { |name = nil, *rest|
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

          text = rest.join(' ').strip
          if text.empty?
            puts "Usage: h queue say <name> <message>"
            next
          end

          meta = q.meta_for(name, :running)
          pane_id = meta&.[]('herdr_pane')
          unless pane_id
            puts "No Herdr pane recorded for '#{name}'"
            next
          end

          h.herdr_client.send_text(pane_id, text)
          h.herdr_client.send_keys(pane_id, 'Enter')
          puts "Sent to #{name} [pane #{pane_id}]"
        }

        h.add_subcmd(:session) {
          work_dir = File.expand_path('~/work')
          h.herdr_client.open_workspace(HERDR_WORKSPACE, start_directory: work_dir)
        }

        do_add = lambda do |args, split: nil, session: false|
          q.queue_dirs
          opts = Hiiro::Options.parse(args) do
            option(:task,        short: :t, desc: 'Task name', flag_ifs: [:find])
            option(:name,        short: :n, desc: 'Base filename for the queue task')
            flag(:find,          short: :f, desc: 'Choose task/session interactively (fuzzyfind)')
            flag(:horizontal,    short: :h, desc: 'Split down in the current Herdr tab')
            flag(:vertical,      short: :v, desc: 'Split right in the current Herdr tab')
            flag(:session,       short: :s, desc: 'Use current Herdr workspace')
            flag(:ignore,        short: :i, desc: 'Background task — no shell after completion')
          end

          if opts.help?
            puts opts.help_text
            exit 1
          end

          split ||= :hsplit if opts.horizontal
          split ||= :vsplit if opts.vertical

          args = opts.args
          ti = q.resolve_task_info(opts, h, task_info)

          if opts.session || session
            ti = (ti || {}).merge(session_name: q.calling_workspace_name)
          end
          template = Prompt.frontmatter_lines(task_info: ti, ignore: opts.ignore, hints: true).join("\n")
          location = q.resolve_prompt_context(Prompt.new(FrontMatterParser::Parser.new(:md).call(template)))
          calling_pane = q.calling_pane!(location) if %i[hsplit vsplit].include?(split)

          # Split+interactive: open the editor and omp in a new Herdr pane.
          if %i[hsplit vsplit].include?(split) && args.empty? && $stdin.tty?
            fm_lines = Prompt.frontmatter_lines(task_info: ti, ignore: opts.ignore, hints: true)

            tmp_dir = File.join(Dir.home, '.config/hiiro/tmp')
            FileUtils.mkdir_p(tmp_dir)
            base        = File.join(tmp_dir, "hq-#{Time.now.strftime('%Y%m%d%H%M%S%L')}")
            prompt_path = "#{base}.md"
            script_path = "#{base}.sh"
            File.write(prompt_path, fm_lines.join("\n"))

            task_base_dir = location.start_directory

            File.write(script_path, <<~SH)
              #!/usr/bin/env bash
              _PROMPT=#{Shellwords.shellescape(prompt_path)}
              _BASE_DIR=#{Shellwords.shellescape(location.root_directory)}
              _IGNORE=#{opts.ignore ? 'true' : 'false'}
              ${EDITOR:-vim} "$_PROMPT" || exit $?
              if [ -s "$_PROMPT" ]; then
                _WD="$(h queue pane-dir "$_PROMPT" "$_BASE_DIR")" || exit $?
                [ -n "$_WD" ] && [ -d "$_WD" ] && cd "$_WD" || exit 1
                _IGNORE="$(h queue pane-ignore "$_PROMPT")" || exit $?
                if [ "$_IGNORE" = true ]; then
                  omp -p "@$_PROMPT"
                else
                  omp "@$_PROMPT"
                fi
              fi
              rm -f #{Shellwords.shellescape(prompt_path)} #{Shellwords.shellescape(script_path)}
              [ "$_IGNORE" = true ] || exec ${SHELL:-zsh}
            SH
            FileUtils.chmod(0755, script_path)

            direction = split == :hsplit ? :down : :right
            h.herdr_client.split_pane(target: calling_pane, direction: direction, start_directory: task_base_dir, command: script_path, focus: true)
            next
          end

          if args.empty? && !$stdin.tty?
            content = $stdin.read.strip
          elsif args.any?
            content = args.join(' ')
          else
            fm_lines = Prompt.frontmatter_lines(task_info: ti, ignore: opts.ignore, hints: true)
            fm_content = fm_lines.join("\n")

            input_directory = location.start_directory

            input = InputFile.md_file(hiiro: h, content: fm_content, append: !!fm_content, prefix: 'hq-')
            Dir.chdir(input_directory) { input.edit }
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
          elsif session
            q.launch_task(result[:name])
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
            flag(:session,   short: :s, desc: 'Use current Herdr workspace')
          end
          args = opts.args
          ti = q.resolve_task_info(opts, h, task_info)

          ti = (ti || {}).merge(session_name: q.calling_workspace_name) if opts.session

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
            fm_lines = Prompt.frontmatter_lines(task_info: ti, hints: true)
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
          if meta&.[]('herdr_pane')
            h.herdr_client.close_pane(meta['herdr_pane'])
          elsif meta&.[]('herdr_tab')
            h.herdr_client.close_tab(meta['herdr_tab'])
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
          do_add.call(args, session: true)
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
        h.add_subcmd(:'pane-dir') { |prompt_path = nil, base_dir = nil|
          print q.resolve_pane_dir(prompt_path.to_s, base_dir)
        }

        h.add_subcmd(:'pane-ignore') { |prompt_path = nil|
          prompt = Prompt.from_file(prompt_path.to_s)
          raise Error, "Prompt file not found" unless prompt
          print prompt.ignore?
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

    # A queue entry's identity and storage: root dirs, name, lifecycle status.
    # Answers every companion path and reads its files; moving is left to callers.
    class Entry
      def self.find(dirs, name)
        STATUSES.each do |status|
          entry = new(dirs: dirs, name: name, status: status.to_sym)
          return entry if entry.exists?
        end
        nil
      end

      def self.in(dirs, status)
        Dir.glob(File.join(dirs.fetch(status), '*.md')).sort.map do |path|
          new(dirs: dirs, name: File.basename(path, '.md'), status: status)
        end
      end

      attr_reader :dirs, :name, :status

      def initialize(dirs:, name:, status:)
        @dirs = dirs
        @name = name
        @status = status
      end

      def dir           = dirs.fetch(status)
      def prompt_path   = File.join(dir, "#{name}.md")
      def meta_path     = File.join(dir, "#{name}.meta")
      def launcher_path = File.join(dir, "#{name}.sh")
      def body_path     = File.join(dir, "#{name}.prompt")

      def companion_files = [prompt_path, meta_path, launcher_path, body_path].select { |p| File.exist?(p) }

      def exists?     = File.exist?(prompt_path)
      def modified_at = File.mtime(prompt_path)
      def running?    = status == :running

      def prompt(hiiro: nil) = Prompt.from_file(prompt_path, hiiro: hiiro)

      def meta
        File.exist?(meta_path) ? YAML.safe_load_file(meta_path) : nil
      end

      # "| first non-blank body line", truncated to width.
      def preview(width: 60)
        return nil unless exists?

        lines = File.readlines(prompt_path, chomp: true)
        if lines.first == '---'
          end_idx = lines[1..].index('---')
          lines = lines[(end_idx + 2)..] if end_idx
        end
        first = lines&.find { |l| !l.strip.empty? }&.strip
        return nil unless first

        first.length > width ? "| #{first[0, width - 3]}..." : "| #{first}"
      end

      # Snapshot of the recorded run; nil when there is no metadata.
      def execution
        data = meta
        data && Execution.new(self, data)
      end

      def moved_to(new_status) = self.class.new(dirs: dirs, name: name, status: new_status.to_sym)

      def to_h = { name: name, status: status.to_s }
    end

    # What the .meta file recorded when an entry was launched.
    class Execution
      attr_reader :entry, :meta

      def initialize(entry, meta)
        @entry = entry
        @meta = meta
      end

      def started_at        = meta['started_at'] && Time.parse(meta['started_at'])
      def working_directory = meta['working_dir']
      def location          = Hiiro::Herdr::Location.from_meta(meta)
      def attach_target     = location.target

      def elapsed(now: Time.now) = started_at && Duration.seconds(now - started_at)
      def elapsed_minutes(now: Time.now) = elapsed(now: now) && (elapsed(now: now).seconds / 60).to_i
    end

    class Prompt
      def self.from_file(path, hiiro: nil)
        return unless File.exist?(path)

        new(FrontMatterParser::Parser.parse_file(path), hiiro:, path: path)
      end

      # The editor template: task context lines, optional ignore flag, and the
      # commented app/dir hints. Returns lines (no trailing newline joined).
      def self.frontmatter_lines(task_info:, ignore: false, hints: false)
        lines = ["---"]
        lines << "task_name: #{task_info[:task_name]}" if task_info&.dig(:task_name)
        lines << "tree_name: #{task_info[:tree_name]}" if task_info&.dig(:tree_name)
        lines << "session_name: #{task_info[:session_name]}" if task_info&.dig(:session_name)
        lines << "ignore: true" if ignore
        if hints
          lines << "# app: <partial-app-name>  (run omp from this app's directory)"
          lines << "# dir: <relative-path>     (subdir within app or tree root)"
        end
        lines << "---"
        lines << ""
        lines
      end

      attr_reader :hiiro, :doc, :frontmatter, :path

      def initialize(doc, hiiro: nil, path: nil)
        @hiiro = hiiro
        @doc = doc
        @path = path
        @frontmatter = doc.front_matter || {}
      end

      # Prompt text without frontmatter.
      def body = doc.content.strip

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
        frontmatter['session_name']
      end
    end
  end
end
