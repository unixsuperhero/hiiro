require 'yaml'
require 'fileutils'
require 'shellwords'
require 'time'
require 'front_matter_parser'
require 'tempfile'

# Load concerns first
require_relative 'concerns/yaml_configurable'
require_relative 'concerns/tmux_integration'
require_relative 'concerns/matchable'
require_relative 'base_commands'

# Define the Queue class with constants first, before loading subfiles
class Hiiro
  class Queue
    DIR = File.join(Dir.home, '.config/hiiro/queue')
    TMUX_SESSION = 'hq'
    STATUSES = %w[wip pending running done failed].freeze
  end
end

# Load queue components (they add classes to Hiiro::Queue)
require_relative 'queue/task'
require_relative 'queue/prompt'
require_relative 'queue/presenter'
require_relative 'queue/manager'
require_relative 'queue/launch'
require_relative 'queue/commands'
require_relative 'queue/actions'

class Hiiro
  class Queue
    class << self
      # Get or create the current queue manager singleton.
      #
      # @param hiiro [Hiiro, nil] optional Hiiro instance
      # @return [Queue::Manager] the queue manager
      def current(hiiro = nil)
        @current ||= Manager.new(hiiro)
      end

      # Build a Hiiro command interface for queue operations.
      #
      # @param parent_hiiro [Hiiro] parent Hiiro instance
      # @param manager [Queue::Manager, nil] queue manager (uses current if nil)
      # @param task_info [Hash, nil] optional task context
      # @return [Hiiro] configured child Hiiro instance
      def build_hiiro(parent_hiiro, manager = nil, task_info: nil)
        manager ||= current(parent_hiiro)
        Commands.new(manager, parent_hiiro, task_info: task_info).build
      end
    end

    # Delegate instance methods to Manager for backwards compatibility
    class << Manager
      def current(hiiro = nil)
        Queue.current(hiiro)
      end
    end
  end

  # Backwards compatibility aliases at the Hiiro level
  QueueTask = Queue::Task
  QueuePresenter = Queue::Presenter
  QueueLaunch = Queue::Launch
  QueueCommands = Queue::Commands
  QueueActions = Queue::Actions
end
