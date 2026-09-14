class Hiiro
  class Notification
    def self.show(hiiro)
      new(hiiro).show
    end

    attr_reader :hiiro, :original_args

    def initialize(hiiro)
      @hiiro = hiiro
      @original_args = hiiro.args.dup
    end

    def options
      @options ||= Options.parse(args) do
        option(:sound, short: :s, default: 'Basso', desc: 'macOS system sound name, or none')
        option(:sound_alias, short: :S, desc: 'alias for -s')
        option(:title, short: :t, desc: 'title')
        option(:message, short: :m, desc: 'message')
        option(:link, short: :l, desc: 'link to open')
        option(:command, short: :c, desc: 'command to run')
      end
    end

    def args
      @args ||= hiiro.args
    end

    # System sound name for terminal-notifier's -sound, or nil for silent.
    # Herdr has its own sounds, so no separate afplay process is started.
    def sound
      name = (options.sound_alias || options.sound).to_s.strip
      return nil if name.empty? || name.casecmp?('none')
      name == 'default' ? name : name.capitalize
    end

    def command
      cmd = [binpath]
      cmd += ['-message', options.message] if options.message
      cmd += ['-title', options.title.tr('()[]', '')] if options.title
      cmd += ['-open', options.link] if options.link
      cmd += ['-execute', options.command] if options.command
      cmd += ['-sound', sound] if sound
      cmd
    end

    def show
      return unless has_cmd?

      Process.detach(spawn(*command))
    end

    def binpath
      `command -v terminal-notifier`.strip
    end

    def has_cmd?
      system("command -v terminal-notifier &>/dev/null")
    end
  end
end

