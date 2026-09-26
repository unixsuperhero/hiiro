require 'time'

class Hiiro
  # A point in time parsed from user input. Retains the raw text and how it was
  # interpreted (unix seconds, unix milliseconds, free text, or 'now').
  class TimeInput
    NUMERIC = /\A-?\d+(\.\d+)?\z/

    # Digits → unix timestamp (milliseconds when ms: true, or when ms is nil and
    # the integer part is longer than 11 digits). nil / '' / 'now' → now.
    # Anything else → Time.parse.
    def self.parse(raw, ms: nil, now: Time.now)
      text = raw.to_s
      if text.match?(NUMERIC)
        n = Rational(text)
        ms = text.sub(/\..*/, '').length > 11 if ms.nil?
        new(raw, ms ? :milliseconds : :seconds, Time.at(ms ? n / 1000 : n))
      elsif text.empty? || text == 'now'
        new(raw, :now, now)
      else
        new(raw, :text, Time.parse(text))
      end
    end

    attr_reader :raw, :unit, :time

    def initialize(raw, unit, time)
      @raw = raw
      @unit = unit
      @time = time
    end

    def unix_seconds      = time.to_i
    def unix_milliseconds = (time.to_f * 1000).round
    def utc               = self.class.new(raw, unit, time.utc)
    def iso8601(digits = 0) = time.iso8601(digits)
    def strftime(fmt)     = time.strftime(fmt)

    # Duration from this time to other.
    def difference(other) = Duration.seconds(other.time - time)
  end
end
