class Hiiro
  class Projects
    def self.add_resolvers(hiiro)
      projects = new
      hiiro.add_resolver(:project, -> { projects.context(selection: projects.pick(chooser: chooser(hiiro))).start_directory }) do |name|
        projects.context(name, chooser: chooser(hiiro)).start_directory
      end
    end

    # The shared picker over [name, path] values; identity is the project name.
    def self.chooser(hiiro = nil)
      Picker.chooser('projects', family: :project, hiiro: hiiro) { |(name, path), label| Picker.project_item(name, path, label: label) }
    end

    def dirs
      Dir.glob(File.join(Dir.home, 'proj', '*/')).map { |path|
        [File.basename(path), path]
      }.to_h
    end

    def from_config
      Project.all_as_hash
    end

    def save_project(name, path)
      existing = Project.find_by_name(name)
      if existing
        existing.update(path: path.to_s)
      else
        Project.create(name: name.to_s, path: path.to_s)
      end
    end

    def from_config?(name)
      from_config.key?(name)
    end

    def all
      dirs.merge(from_config)
    end

    def pick(chooser: Projects.chooser, tty: $stdin.tty?, candidates: all.to_a)
      raise Hiiro::Error, 'No projects found' if candidates.empty?
      raise Hiiro::Error, 'Project selection requires a TTY; supply a project name' unless tty

      configured = from_config
      mapping = candidates.to_h do |name, path|
        [format('%-15s %-8s %s', name, configured.key?(name) ? '[config]' : '[dir]', path), [name, path]]
      end
      selected = chooser.call(mapping)
      raise Hiiro::Error, 'Project selection cancelled' unless selected
      raise Hiiro::Error, 'Invalid project selection' unless mapping.values.include?(selected)
      selected
    end

    def resolve(name, chooser: Projects.chooser, tty: $stdin.tty?)
      return ['proj', File.join(Dir.home, 'proj')] if name.nil?
      raise Hiiro::Error, 'Project name cannot be empty' if name.strip.empty?

      result = Matcher.by_prefix(all, name) { |project_name, _| project_name }
      return result.resolved.item if result.resolved
      raise Hiiro::Error, "Project '#{name}' not found" unless result.match?
      unless tty
        raise Hiiro::Error, "Ambiguous project '#{name}': #{result.matches.map { |match| match.item.first }.join(', ')}"
      end
      pick(chooser: chooser, tty: tty, candidates: result.matches.map(&:item))
    end

    def find(name, **options)
      _, path = resolve(name, **options)
      File.expand_path(path)
    end

    def context(name = nil, chooser: Projects.chooser, tty: $stdin.tty?, invocation_directory: Dir.pwd,
                terminal: Herdr::Location.from_env, selection: nil)
      project_name, path = selection || resolve(name, chooser: chooser, tty: tty)
      identity = Project.find_by_name(project_name) || project_name
      TaskLocation.for(nil, root: path, root_source: :project, project: identity,
                       invocation_directory: invocation_directory, terminal: terminal)
    end
  end
end
