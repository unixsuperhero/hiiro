class Hiiro
  class App
    attr_reader :name, :relative_path

    def initialize(name:, path:)
      @name = name
      @relative_path = path
    end

    def resolve(tree_root)
      File.join(tree_root, relative_path)
    end

    def ==(other)
      other.is_a?(App) && name == other.name
    end

    def to_s
      name
    end
  end
end
