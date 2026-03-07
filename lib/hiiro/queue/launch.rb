require 'shellwords'
require 'fileutils'

class Hiiro
  class Queue
    # Orchestrates launching a queue task in tmux.
    # Moves the task to running, creates a tmux window, and executes claude.
    class Launch
      include TmuxIntegration

      attr_reader :task, :queue, :hiiro

      # @param task [Queue::Task] the task to launch
      # @param queue [Queue::Manager] the queue manager
      # @param hiiro [Hiiro, nil] optional Hiiro instance for environment access
      def initialize(task, queue, hiiro: nil)
        @task = task
        @queue = queue
        @hiiro = hiiro
      end

      # Execute the launch process.
      #
      # @return [Boolean] true if launched successfully
      def call
        return false unless move_to_running
        return false unless (prompt_obj = load_prompt)

        target = resolve_target(prompt_obj)
        ensure_session_exists(target[:session], working_dir: target[:working_dir])
        write_files(prompt_obj, target)
        create_tmux_window_for_task(target)
        write_meta(prompt_obj, target)

        puts "Launched: #{task.name} [#{target[:session]}:#{target[:window_name]}]"
        true
      end

      private

      def move_to_running
        src = queue.task_path(task.name, :pending)
        return false unless File.exist?(src)

        dst = queue.task_path(task.name, :running)
        FileUtils.mv(src, dst)
        true
      end

      def load_prompt
        running_md = queue.task_path(task.name, :running)
        Prompt.from_file(running_md, hiiro: hiiro)
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
          window_name: queue.window_name(task.name)
        }
      end

      def write_files(prompt_obj, target)
        prompt_body = prompt_obj&.content || raw_content_without_frontmatter

        File.write(queue.prompt_path(task.name), prompt_body + "\n")
        write_launcher_script(target)
      end

      def raw_content_without_frontmatter
        running_md = queue.task_path(task.name, :running)
        raw = File.read(running_md)
        Prompt.new(FrontMatterParser::Parser.new(:md).call(raw)).content
      end

      def write_launcher_script(target)
        script_content = <<~SH
          #!/usr/bin/env bash

          cd #{Shellwords.shellescape(target[:working_dir])}
          cat #{Shellwords.shellescape(queue.prompt_path(task.name))} | claude
          HQ_EXIT=$?

          # Move task files to done/failed based on exit code
          ruby -e '
            require "fileutils"
            name = #{task.name.inspect}
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

        path = queue.script_path(task.name)
        File.write(path, script_content)
        FileUtils.chmod(0755, path)
      end

      def create_tmux_window_for_task(target)
        system('tmux', 'new-window', '-d', '-t', target[:session],
               '-n', target[:window_name], '-c', target[:working_dir],
               queue.script_path(task.name))
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

        File.write(queue.meta_path(task.name, :running), meta.to_yaml)
      end
    end
  end
end
