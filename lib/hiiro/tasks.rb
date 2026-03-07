require 'yaml'
require 'fileutils'

# Load concerns first
require_relative 'concerns/matchable'
require_relative 'base_commands'

# Define TaskManager stub before loading config (which defines Config inside it)
class Hiiro
  class TaskManager
  end
end

# Load task components (they add classes to Hiiro and Hiiro::TaskManager)
require_relative 'task/task'
require_relative 'task/app'
require_relative 'task/tree'
require_relative 'task/tmux_session'
require_relative 'task/config'
require_relative 'task/environment'
require_relative 'task/presenter'
require_relative 'task/manager'
require_relative 'task/start'
require_relative 'task/switch'
require_relative 'task/app_resolution'
require_relative 'task/selection'
require_relative 'task/commands'
require_relative 'task/actions'

class Hiiro
  class TaskManager
    TASKS_DIR = Config::TASKS_DIR
    APPS_FILE = Config::APPS_FILE

    class << self
      # Build a Hiiro command interface for task operations.
      #
      # @param parent_hiiro [Hiiro] parent Hiiro instance
      # @param manager [TaskManager::Manager] task manager
      # @return [Hiiro] configured child Hiiro instance
      def build_hiiro(parent_hiiro, manager)
        TaskCommands.new(manager, parent_hiiro).build
      end
    end

    # Delegate to Manager for backwards compatibility
    # This allows TaskManager.new to still work
    def self.new(hiiro, scope: :task, environment: nil)
      Manager.new(hiiro, scope: scope, environment: environment)
    end
  end

  # Module interface for building task Hiiro instances
  module Tasks
    def self.build_hiiro(parent_hiiro, tm)
      TaskCommands.new(tm, parent_hiiro).build
    end
  end
end
