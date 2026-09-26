class Hiiro
  # A span of time. Retains the raw input (when parsed from text) and the
  # exact number of seconds; answers components and display forms.
  class Duration
    UNITS = { 's' => 1, 'm' => 60, 'h' => 3_600, 'd' => 86_400, 'w' => 604_800 }.freeze
    PATTERN = /\A(\d+)([smhdw])\z/i

    # '15m' → Duration. Returns nil when the text is not <digits><unit>.
    def self.parse(raw)
      match = raw.to_s.match(PATTERN)
      return nil unless match

      new(match[1].to_i * UNITS.fetch(match[2].downcase), raw: raw)
    end

    def self.seconds(n)      = new(n)
    def self.milliseconds(n) = new(Rational(n) / 1000)

    attr_reader :raw, :seconds

    def initialize(seconds, raw: nil)
      @seconds = seconds
      @raw = raw
    end

    def milliseconds = (seconds.to_f * 1000).round
    def negative?    = seconds.to_f.negative?

    # Absolute, whole-second breakdown: { days:, hours:, minutes:, seconds: }
    def components
      total = seconds.to_f.abs.round
      days, rem     = total.divmod(86_400)
      hours, rem    = rem.divmod(3_600)
      minutes, secs = rem.divmod(60)
      { days: days, hours: hours, minutes: minutes, seconds: secs }
    end

    # 1d23h12m10s, 0s, -3m
    def compact
      c = components
      parts = []
      parts << "#{c[:days]}d"    if c[:days] > 0
      parts << "#{c[:hours]}h"   if c[:hours] > 0
      parts << "#{c[:minutes]}m" if c[:minutes] > 0
      parts << "#{c[:seconds]}s" if c[:seconds] > 0
      (negative? ? '-' : '') + (parts.empty? ? '0s' : parts.join)
    end

    # HH:MM:SS (days folded into hours)
    def clock
      c = components
      format('%02d:%02d:%02d', c[:days] * 24 + c[:hours], c[:minutes], c[:seconds])
    end

    def +(other) = self.class.new(seconds + other.seconds)
    def -(other) = self.class.new(seconds - other.seconds)
    def ==(other) = other.is_a?(Duration) && seconds == other.seconds

    def to_s = compact
  end
end
