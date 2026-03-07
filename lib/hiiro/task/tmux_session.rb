class Hiiro
  # Value object representing a tmux session.
  class TmuxSession
    attr_reader :name

    # Get the current tmux session.
    #
    # @return [TmuxSession, nil] current session or nil if not in tmux
    def self.current
      return nil unless ENV['TMUX']
      name = `tmux display-message -p '#S'`.chomp
      new(name)
    end

    # Get all tmux sessions.
    #
    # @return [Array<TmuxSession>] list of sessions
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
