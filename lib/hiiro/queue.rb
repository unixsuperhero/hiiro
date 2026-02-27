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
