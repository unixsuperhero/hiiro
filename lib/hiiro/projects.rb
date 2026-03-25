require 'yaml'

class Hiiro
  class Projects
    CONFIG_FILE = File.join(Dir.home, '.config', 'hiiro', 'projects.yml')

    def self.add_resolvers(hiiro)
      pm = new
      hiiro.add_resolver(:project,
        -> {
          all = pm.all
          return nil if all.empty?
          conf = pm.from_config
          lines = all.each_with_object({}) do |(name, path), h|
            source = conf.key?(name) ? '[config]' : '[dir]'
            h[format("%-15s %-8s %s", name, source, path)] = path
          end
          hiiro.fuzzyfind_from_map(lines)
        }
      ) do |name|
        pm.find(name)
      end
    end

    def dirs
      Dir.glob(File.join(Dir.home, 'proj', '*/')).map { |path|
        [File.basename(path), path]
      }.to_h
    end

    def from_config
      return {} unless File.exist?(CONFIG_FILE)
      YAML.safe_load_file(CONFIG_FILE) || {}
    end

    def from_config?(name)
      from_config.key?(name)
    end

    def all
      dirs.merge(from_config)
    end

    # Find a project path by name (regex match, exact-match tiebreak).
    # Returns the path string, or nil if 0 or >1 matches.
    def find(name)
      re = /#{name}/i
      conf = from_config
      matches = dirs.select { |k, _| k.match?(re) }.merge(conf.select { |k, _| k.match?(re) })
      matches = matches.select { |k, _| k == name } if matches.count > 1
      matches.count == 1 ? matches.values.first : nil
    end
  end
end
