require 'yaml'
require 'fileutils'
require 'time'
require 'ostruct'

# Load concerns first
require_relative 'concerns/yaml_configurable'
require_relative 'concerns/tmux_integration'
require_relative 'concerns/matchable'
require_relative 'base_commands'

# Define the ServiceManager class with constants first, before loading subfiles
class Hiiro
  class ServiceManager
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'services.yml')
    STATE_DIR = File.join(Dir.home, '.config', 'hiiro', 'services')
    STATE_FILE = File.join(STATE_DIR, 'running.yml')
    ENV_TEMPLATES_DIR = File.join(Dir.home, '.config', 'hiiro', 'env_templates')
  end
end

# Load service components (they add classes to Hiiro::ServiceManager)
require_relative 'service/service'
require_relative 'service/member'
require_relative 'service/group'
require_relative 'service/presenter'
require_relative 'service/manager'
require_relative 'service/launch'
require_relative 'service/stop'
require_relative 'service/group_launch'
require_relative 'service/env_preparation'
require_relative 'service/commands'
require_relative 'service/actions'

class Hiiro
  class ServiceManager
    class << self
      # Build a Hiiro command interface for service operations.
      #
      # @param parent_hiiro [Hiiro] parent Hiiro instance
      # @param manager [ServiceManager::Manager] service manager
      # @param task_manager [TaskManager, nil] optional task manager for context
      # @return [Hiiro] configured child Hiiro instance
      def build_hiiro(parent_hiiro, manager, task_manager: nil)
        Commands.new(manager, parent_hiiro, task_manager: task_manager).build
      end
    end

    # Delegate to Manager for backwards compatibility
    # This allows ServiceManager.new to still work
    def self.new(config_file: CONFIG_FILE, state_file: STATE_FILE)
      Manager.new(config_file: config_file, state_file: state_file)
    end
  end

  # Backwards compatibility aliases at the Hiiro level
  Service = ServiceManager::Service
  ServiceGroup = ServiceManager::Group
  GroupMember = ServiceManager::Member
  ServiceLaunch = ServiceManager::Launch
  ServiceStop = ServiceManager::Stop
  GroupLaunch = ServiceManager::GroupLaunch
  EnvPreparation = ServiceManager::EnvPreparation
  ServicePresenter = ServiceManager::Presenter
  ServiceCommands = ServiceManager::Commands
  ServiceActions = ServiceManager::Actions
end
