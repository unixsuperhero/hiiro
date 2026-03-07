require 'yaml'
require 'fileutils'
require 'time'

class Hiiro
  class Queue
    # Core queue manager responsible for task storage and lifecycle.
    # Handles low-level operations like path resolution, task lookup, and state management.
    class Manager
      include YamlConfigurable
      include TmuxIntegration

      attr_reader :hiiro

      def initialize(hiiro = nil)
        @hiiro = hiiro
      end

      # --- Directory Management ---

      def queue_dirs
        @queue_dirs ||= STATUSES.each_with_object({}) do |name, h|
          dir = File.join(DIR, name)
          FileUtils.mkdir_p(dir)
          h[name.to_sym] = dir
        end
      end

      # --- Path Accessors (noun-named per Phase 5) ---

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

      # --- Task Enumeration ---

      def tasks_in(status)
        dir = queue_dirs[status]
        Dir.glob(File.join(dir, '*.md')).sort.map { |f| File.basename(f, '.md') }
      end

      def all_tasks
        STATUSES.flat_map do |status|
          tasks_in(status.to_sym).map { |name| Task.new(name: name, status: status, queue: self) }
        end
      end

      def find_task(name)
        STATUSES.each do |status|
          md = task_path(name, status.to_sym)
          return Task.new(name: name, status: status, queue: self) if File.exist?(md)
        end
        nil
      end

      def meta_for(name, status)
        path = meta_path(name, status)
        File.exist?(path) ? YAML.safe_load_file(path) : nil
      end

      # --- Naming Helpers (noun-named per Phase 5) ---

      def slug(text)
        text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
      end

      # Generate a short window name, avoiding collisions.
      def window_name(name)
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

      # Generate a unique task name from content.
      def task_name_for(content, task_info: nil)
        content_lines = content.lines.drop_while { |l| l.strip.empty? || l.start_with?('---') || l.match?(/^\w+:/) }.first.to_s.strip
        name = slug(content_lines)

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

      # --- Frontmatter Building (noun-named per Phase 5) ---

      def frontmatter_for(task_info)
        return nil unless task_info

        fm = {}
        fm['task_name'] = task_info[:task_name] if task_info[:task_name]
        fm['tree_name'] = task_info[:tree_name] if task_info[:tree_name]
        fm['session_name'] = task_info[:session_name] if task_info[:session_name]

        return nil if fm.empty?

        "---\n#{fm.map { |k, v| "#{k}: #{v}" }.join("\n")}\n---\n"
      end

      def content_with_frontmatter(content, task_info: nil)
        frontmatter = frontmatter_for(task_info)
        frontmatter ? "#{frontmatter}#{content}" : content
      end

      # --- Task Resolution ---

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

      # --- Task Operations ---

      def add_task(content, task_info: nil)
        queue_dirs # ensure dirs exist
        content = content_with_frontmatter(content, task_info: task_info)
        name = task_name_for(content, task_info: task_info)
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

      def launch_task(name)
        task = Task.new(name: name, status: 'pending', queue: self)
        Launch.new(task, self, hiiro: hiiro).call
      end

      # --- Legacy Compatibility ---

      def add_with_frontmatter(content, task_info: nil)
        add_task(content, task_info: task_info)
      end

    end
  end
end
