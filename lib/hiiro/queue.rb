require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'

class Hiiro
  class Queue
    DIR = File.join(Dir.home, '.config/hiiro/queue')
    TMUX_SESSION = 'hq'
    STATUSES = %w[wip pending running done failed].freeze

    def self.current
      @current ||= new
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

      prompt = File.read(running_md).strip

      ensure_tmux_session

      # Build the cleanup script that runs after claude exits
      # Capture claude's exit code in $HQ_EXIT, then use it in the ruby cleanup
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
      shell_cmd = "claude #{Shellwords.shellescape(prompt)}; HQ_EXIT=$?; #{cleanup_ruby}; exec #{ENV['SHELL'] || 'zsh'}"

      system('tmux', 'new-window', '-t', TMUX_SESSION, '-n', name, shell_cmd)

      # Write meta sidecar
      meta = {
        'tmux_session' => TMUX_SESSION,
        'tmux_window' => name,
        'started_at' => Time.now.iso8601,
        'working_dir' => Dir.pwd,
      }
      File.write(File.join(dirs[:running], "#{name}.meta"), meta.to_yaml)

      puts "Launched: #{name}"
    end

    def slugify(text)
      text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0, 60]
    end
  end
end
