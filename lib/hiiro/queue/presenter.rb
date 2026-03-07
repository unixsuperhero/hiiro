require 'time'

class Hiiro
  class Queue
    # Presentation layer for queue output formatting.
    module Presenter
      module_function

      # Generate a preview of a task's prompt content.
      #
      # @param path [String] path to the markdown file
      # @return [String, nil] preview text or nil
      def task_preview(path)
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

      # Format a task line for list output.
      #
      # @param task [Queue::Task] the task to format
      # @param queue [Queue::Manager] the queue manager for path resolution
      # @return [String] formatted line
      def format_task_line(task, queue)
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

        preview = task_preview(task.path)
        line += "  #{preview}" if preview
        line
      end

      # Format a detailed status line for a task.
      #
      # @param task [Queue::Task] the task to format
      # @param queue [Queue::Manager] the queue manager
      # @return [String] formatted line
      def format_status_line(task, queue)
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
  end
end
