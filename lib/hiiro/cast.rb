require 'date'
require 'shellwords'
require_relative 'error'

class Hiiro
  # Dated terminal casts: DIR/YYYYMMDDNNN.cast, NNN counting up from 000
  # within a day. Directory and editor recipe are personal profile policy
  # (section casts).
  #
  #   casts = Hiiro::Cast.from_profile
  #   casts.path(:next)                         # => "~/casts/20261013002.cast" when 000 and 001 exist
  #   casts.path(4, day: Cast.day('20261001'))  # => "~/casts/20261001004.cast"
  #   casts.record_command(['notes.md'])        # => "vi notes.md"
  class Cast
    KINDS = %i[first previous current last next].freeze

    DEFAULTS = {
      'dir' => '~/casts',
      'editor' => ENV.fetch('EDITOR', 'vi'),
      'resume_args' => ['+norm! g`"'],
    }.freeze

    def self.from_profile(profile = Profile.load)
      section = profile.section('casts', DEFAULTS)
      new(dir: section.path('dir'), editor: section.argv('editor'), resume_args: section.argv('resume_args'))
    end

    # '0', '-7', '+1' => relative to today; 'YYYYMMDD' => that day.
    def self.day(value = '0', today: Date.today)
      value.match?(/\A[+-]?\d+\z/) && value.length < 8 ? today + Integer(value, 10) : Date.strptime(value, '%Y%m%d')
    rescue ArgumentError
      raise Error, "invalid day: #{value.inspect} (use a relative day like -7 or YYYYMMDD)"
    end

    def self.index(value)
      index = Integer(value, 10)
      raise Error, "invalid index: #{value.inspect}" if index.negative?

      index
    rescue ArgumentError
      raise Error, "invalid index: #{value.inspect}"
    end

    attr_reader :dir, :editor, :resume_args

    def initialize(dir:, editor:, resume_args: [])
      @dir = dir
      @editor = editor
      @resume_args = resume_args
    end

    def indices(day)
      prefix = day.strftime('%Y%m%d')
      Dir.glob(File.join(dir, "#{prefix}[0-9][0-9][0-9].cast")).filter_map do |path|
        File.basename(path).match(/\A#{prefix}(\d{3})\.cast\z/)&.captures&.first&.to_i
      end
    end

    # The one naming operation: a kind (first/previous/current/last/next)
    # or an explicit Integer index, on a day.
    def path(which, day: Date.today)
      index = which.is_a?(Integer) ? which : index_for(which, day)
      raise Error, "invalid index: #{index.inspect}" if index.negative?

      File.join(dir, format('%s%03d.cast', day.strftime('%Y%m%d'), index))
    end

    def record_command(files) = command([*editor, *files])
    def resume_command(files) = command([*editor, *resume_args, *files])

    private

    def index_for(kind, day)
      found = indices(day)
      current = found.max || 0
      case kind
      when :first then 0
      when :previous then [current - 1, 0].max
      when :current, :last then current
      when :next then found.empty? ? 0 : current + 1
      else raise ArgumentError, "unknown cast kind: #{kind.inspect}"
      end
    end

    # asciinema runs the command through a shell.
    def command(argv)
      raise Error, "casts.editor is not set (#{Profile.path})" if editor.empty?

      Shellwords.join(argv)
    end
  end
end
