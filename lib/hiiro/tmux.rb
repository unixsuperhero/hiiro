class Hiiro
  class Tmux
    def self.client!(hiiro = nil)
      @client = new(hiiro)
    end

    def self.client(hiiro = nil)
      return @client if @client && @client.hiiro == hiiro

      if hiiro
        client!(hiiro)
      else
        new
      end
    end

    def self.open_session(name)
      client.open_session(name)
    end

    attr_reader :hiiro

    def initialize(hiiro = nil)
      @hiiro = hiiro
    end

    def open_session(name)
      session_name = name.to_s

      unless system('tmux', 'has-session', '-t', session_name)
        system('tmux', 'new', '-d', '-A', '-s', session_name)
      end

      if ENV['TMUX']
        system('tmux', 'switchc', '-t', session_name)
      elsif ENV['NVIM']
        puts "Can't attach to tmux inside a vim terminal"
      else
        system('tmux', 'new', '-A', '-s', session_name)
      end
    end

    def sessions

    end
  end
end
