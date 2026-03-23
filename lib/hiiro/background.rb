class Hiiro
  module Background
    SESSION = 'h-bg'

    # Run cmd asynchronously. Inside tmux, spins up a hidden window in the
    # h-bg session so you can attach and inspect if needed. Outside tmux,
    # falls back to a detached spawn.
    def self.run(*cmd)
      if inside_tmux?
        ensure_session
        system('tmux', 'new-window', '-d', '-t', "#{SESSION}:", '-n', cmd.first.to_s, cmd.shelljoin)
      else
        Process.detach(spawn(*cmd))
      end
    rescue
      nil
    end

    def self.inside_tmux?
      ENV['TMUX'] && !ENV['TMUX'].empty?
    end

    def self.ensure_session
      unless system('tmux', 'has-session', '-t', SESSION, out: File::NULL, err: File::NULL)
        system('tmux', 'new-session', '-d', '-s', SESSION, out: File::NULL, err: File::NULL)
      end
    end
  end
end
