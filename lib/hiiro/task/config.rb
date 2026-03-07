require 'yaml'
require 'fileutils'

class Hiiro
  class TaskManager
    # Manages task and app configuration persistence.
    # Handles loading/saving tasks.yml and apps.yml.
    class Config
      TASKS_DIR = File.join(Dir.home, '.config', 'hiiro', 'tasks')
      APPS_FILE = File.join(Dir.home, '.config', 'hiiro', 'apps.yml')

      attr_reader :tasks_file, :apps_file

      def initialize(tasks_file: nil, apps_file: nil)
        @tasks_file = tasks_file || File.join(TASKS_DIR, 'tasks.yml')
        @apps_file = apps_file || APPS_FILE
      end

      # Get all tasks from configuration.
      #
      # @return [Array<Task>] list of tasks
      def tasks
        data = load_tasks
        (data['tasks'] || []).map { |h| Task.new(**h.transform_keys(&:to_sym)) }
      end

      # Get all apps from configuration.
      #
      # @return [Array<App>] list of apps
      def apps
        return [] unless File.exist?(apps_file)
        data = YAML.safe_load_file(apps_file) || {}
        data.map { |name, path| App.new(name: name, path: path) }
      end

      # Save a task to configuration.
      #
      # @param task [Task] task to save
      def save_task(task)
        data = load_tasks
        data['tasks'] ||= []
        data['tasks'].reject! { |t| t['name'] == task.name }
        data['tasks'] << task.to_h.transform_keys(&:to_s)
        save_tasks(data)
      end

      # Remove a task from configuration.
      #
      # @param name [String] task name to remove
      def remove_task(name)
        data = load_tasks
        data['tasks'] ||= []
        data['tasks'].reject! { |t| t['name'] == name }
        save_tasks(data)
      end

      private

      def load_tasks
        if File.exist?(tasks_file)
          return YAML.safe_load_file(tasks_file) || { 'tasks' => [] }
        end

        task_files = Dir.glob(File.join(File.dirname(tasks_file), 'task_*.yml'))
        if task_files.any?
          tasks = task_files.map do |file|
            short_name = File.basename(file, '.yml').sub(/^task_/, '')
            data = YAML.safe_load_file(file) || {}
            parent = data['parent']
            if parent.nil? && data['tree']&.include?('/')
              parent = data['tree'].split('/').first
            end
            name = parent ? "#{parent}/#{short_name}" : short_name
            h = { 'name' => name }
            h['tree'] = data['tree'] if data['tree']
            h['session'] = data['session'] if data['session']
            h
          end
          return { 'tasks' => tasks }
        end

        assignments_file = File.join(File.dirname(tasks_file), 'assignments.yml')
        if File.exist?(assignments_file)
          raw = YAML.safe_load_file(assignments_file) || {}
          tasks = raw.map do |tree_path, task_name|
            h = { 'name' => task_name, 'tree' => tree_path }
            h['session'] = task_name if task_name.include?('/')
            h
          end
          data = { 'tasks' => tasks }
          save_tasks(data)
          return data
        end

        { 'tasks' => [] }
      end

      def save_tasks(data)
        FileUtils.mkdir_p(File.dirname(tasks_file))
        File.write(tasks_file, YAML.dump(data))
      end
    end
  end
end
