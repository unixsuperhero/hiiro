class Hiiro
  class Notification
    def self.send(hiiro)
      new(hiiro).send
    end

    attr_reader :hiiro, :original_args

    def initialize(hiiro)
      @hiiro = hiiro
      @original_args = hiiro.args.dup
    end

    def args
      @args ||= hiiro.args
    end

    def sounds
      system = Dir.glob('/System/Library/Sounds/*')
      custom = Dir.glob(File.join(Dir.home, '.config/hiiro/sounds/*'))

      all_sounds = system + custom
      all_sounds.each_with_object({}) do |fn, h|
        basename = File.basename(fn, File.extname(fn))
        puts basename: basename
      end
    end
  end
end

