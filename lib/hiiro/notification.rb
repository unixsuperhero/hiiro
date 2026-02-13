class Hiiro
  class Notification
    def self.show(hiiro)
      new(hiiro).send
    end

    attr_reader :hiiro, :original_args

    def initialize(hiiro)
      @hiiro = hiiro
      @original_args = hiiro.args.dup
    end

    def options
      @options ||= Options.parse(args) do
        option(:sound, short: :s, default: 'basso', desc: 'sound name')
        option(:title, short: :t, desc: 'title')
        option(:message, short: :m, desc: 'message')
        option(:link, short: :l, desc: 'link to open')
        option(:command, short: :c, desc: 'command to run')
      end
    end

    def args
      @args ||= hiiro.args
    end

    def sounds
      custom = Dir.glob(File.join(Dir.home, '.config/hiiro/sounds/*'))

      @sounds ||= custom.each_with_object({}) do |fn, h|
        basename = File.basename(fn, File.extname(fn))
        h[basename.downcase] = fn
      end
    end

    def show
      cmd = ['terminal-notifier']
      cmd << ['-message', options.message] if options.message
      cmd << ['-title', options.title.tr('()[]', '')] if options.title
      cmd << ['-open', options.link] if options.link
      cmd << ['-execute', options.command] if options.command
      system(*cmd)

      play_sound
    end

    def play_sound
      if options.sound && sounds[options.sound]
        system('afplay', sounds[options.sound.downcase])
      end
    end
  end
end

