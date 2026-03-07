class Hiiro
  # Handles app path resolution within a task context.
  # Resolves app names to absolute paths, with fallback to direct paths.
  class AppResolution
    attr_reader :environment, :task

    def initialize(environment, task)
      @environment = environment
      @task = task
    end

    # Resolve an app name to its path.
    #
    # @param app_name [String] the app name to resolve
    # @return [Array<String, String>, nil] [resolved_name, path] or nil
    def path_for(app_name)
      tree = environment.find_tree(task.tree_name)
      tree_root = tree ? tree.path : File.join(Hiiro::WORK_DIR, task.tree_name)

      result = environment.app_matcher.find_all(app_name)

      case result.count
      when 0
        try_direct_paths(tree_root, app_name)
      when 1
        app = result.first.item
        [app.name, app.resolve(tree_root)]
      else
        exact = result.matches.find { |m| m.item.name == app_name }
        if exact
          [exact.item.name, exact.item.resolve(tree_root)]
        else
          puts "ERROR: '#{app_name}' matches multiple apps:"
          result.matches.each { |m| puts "  #{m.item.name}" }
          nil
        end
      end
    end

    private

    def try_direct_paths(tree_root, app_name)
      exact = File.join(tree_root, app_name)
      return [app_name, exact] if Dir.exist?(exact)

      nested = File.join(tree_root, app_name, app_name)
      return [app_name, nested] if Dir.exist?(nested)

      puts "ERROR: App '#{app_name}' not found"
      TaskPresenter.print_apps(environment.all_apps)
      nil
    end
  end
end
