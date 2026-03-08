class Hiiro
  class TmuxSession
    attr_reader :name

    def self.current
      return nil unless ENV['TMUX']

      name = `tmux display-message -p '#S'`.chomp
      new(name)
    end

    def self.all
      output = `tmux list-sessions -F '#S' 2>/dev/null`
      output.lines(chomp: true).map { |name| new(name) }
    end

    def initialize(name)
      @name = name
    end

    def ==(other)
      other.is_a?(TmuxSession) && name == other.name
    end

    def to_s
      name
    end
  end
end
