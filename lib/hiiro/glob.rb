class Hiiro
  class Glob
    def self.brace(*list)
      "{#{list.flatten.compact.join(?,)}}"
    end
  end
end
