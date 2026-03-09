class Hiiro
  class Environment
    attr_reader :path

    def self.current
      new(path: Dir.pwd)
    end

    def initialize(path: Dir.pwd, config: nil)
      @path = path
      @config = config
    end

    def config
      @config ||= TaskManager::Config.new
    end

    def all_tasks
      @all_tasks ||= config.tasks
    end

    def all_sessions
      @all_sessions ||= TmuxSession.all
    end

    def all_trees
      @all_trees ||= Tree.all
    end

    def all_apps
      @all_apps ||= config.apps
    end

    def tree_matcher
      @tree_matcher ||= Hiiro::Matcher.new(all_trees, :name)
    end

    def session_matcher
      @session_matcher ||= Hiiro::Matcher.new(all_sessions, :name)
    end

    def app_matcher
      @app_matcher ||= Hiiro::Matcher.new(all_apps, :name)
    end

    def task_matcher
      @task_matcher ||= Hiiro::Matcher.new(all_tasks, :name)
    end

    def task
      @task ||= begin
        s = session
        t = tree
        all_tasks.find { |task|
          (s && task.session_name == s.name) ||
            (t && task.tree_name == t.name)
        }
      end
    end

    def session
      @session ||= TmuxSession.current
    end

    def tree
      @tree ||= all_trees.find { |t| t.match?(path) }
    end

    def find_task(abbreviated)
      return nil if abbreviated.nil?

      if abbreviated.include?('/')
        result = task_matcher.resolve_path(abbreviated)
        return result.resolved&.item if result.match?

        parent_prefix, child_prefix = abbreviated.split('/', 2)
        if 'main'.start_with?(child_prefix)
          return task_matcher.find(parent_prefix).first&.item
        end

        nil
      else
        task_matcher.find(abbreviated).first&.item
      end
    end

    def find_tree(abbreviated)
      return nil if abbreviated.nil?
      tree_matcher.find(abbreviated).first&.item
    end

    def find_session(abbreviated)
      return nil if abbreviated.nil?
      session_matcher.find(abbreviated).first&.item
    end

    def find_app(abbreviated)
      return nil if abbreviated.nil?
      app_matcher.find(abbreviated).first&.item
    end
  end
end
