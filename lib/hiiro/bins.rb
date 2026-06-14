class Hiiro
  class Bins
    PATH = ENV['PATH']

    def self.path = PATH
    def self.paths = path.split(?:).map(&:strip).uniq

    def self.glob(*names)
      path_glob = [?{, paths.join(?,), ?}].join
      name_glob = [?{, names.flatten.compact.join(?,), ?}].join

      Dir[File.join(path_glob, name_glob)].select(&File.method(:executable?))
    end

    def self.all
      Dir[glob('*')].select(&File.method(:executable?))
    end
  end
end
