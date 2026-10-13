require 'time'
require_relative 'time_input'
require_relative 'duration'

class Hiiro
  # The registrations shared by `h date` and `h time`. Both parse and measure
  # through TimeInput and Duration; a Kind holds the only differences: the
  # noun in usage errors, how a parsed point prints, and what `now` prints.
  #
  #   Registration{ names: [:from_unix, :parse], opts: [:ms, :utc], usage: 'from_unix <timestamp> [--ms] [--utc]',
  #                 missing: ->(args) { args[0].nil? }, run: ->(opts, kind) { ... } }
  #   Kind{ noun: 'time', point: ->(t) { t.strftime('%H:%M:%S.%L') }, now_opts: [:ms, :utc], now: ->(t, ms) { ... } }
  #
  #   Hiiro.run(*ARGV) { Hiiro::TimeCommands.register(self, :time) }
  module TimeCommands
    Kind = Struct.new(:noun, :point, :now_opts, :now, keyword_init: true)
    Registration = Struct.new(:names, :opts, :usage, :missing, :run, keyword_init: true)

    KINDS = {
      date: Kind.new(noun: 'date', point: ->(t) { t.iso8601(3) }, now_opts: %i[utc], now: ->(t, _ms) { t.iso8601 }),
      time: Kind.new(noun: 'time', point: ->(t) { t.strftime('%H:%M:%S.%L') }, now_opts: %i[ms utc],
                     now: ->(t, ms) { t.strftime(ms ? '%H:%M:%S.%L' : '%H:%M:%S') }),
    }.freeze

    def self.input(raw, opts) = TimeInput.parse(raw, ms: opts.ms ? true : nil)
    def self.clock(opts) = opts.utc ? Time.now.utc : Time.now

    # strftime with % inserted before each letter; a literal % stays literal.
    def self.with_percent(chars) = chars.gsub(/[A-Za-z%]/) { |c| c == '%' ? '%%' : "%#{c}" }

    REGISTRATIONS = [
      Registration.new(names: %i[to_unix unix ts], opts: %i[ms], usage: nil, run: lambda do |opts, _kind|
        t = TimeInput.parse(opts.args.join(' '))
        opts.ms ? t.unix_milliseconds : t.unix_seconds
      end),
      Registration.new(names: %i[from_unix parse], opts: %i[ms utc], usage: 'from_unix <timestamp> [--ms] [--utc]',
                       missing: ->(args) { args[0].nil? }, run: lambda do |opts, kind|
        t = input(opts.args.first, opts)
        t = t.utc if opts.utc
        kind.point.call(t)
      end),
      Registration.new(names: %i[fmt format strftime], opts: %i[utc], usage: 'fmt <strftime-chars-without-percent>',
                       missing: ->(args) { args.join(' ').empty? }, run: lambda do |opts, _kind|
        clock(opts).strftime(with_percent(opts.args.join(' ')))
      end),
      Registration.new(names: %i[now], opts: nil, usage: nil, run: ->(opts, kind) { kind.now.call(clock(opts), kind.now_opts.include?(:ms) && opts.ms) }),
      Registration.new(names: %i[dur duration human], opts: %i[ms], usage: 'dur <seconds> [--ms]',
                       missing: ->(args) { args[0].nil? }, run: lambda do |opts, _kind|
        n = Rational(opts.args.first.to_s)
        (opts.ms ? Duration.milliseconds(n) : Duration.seconds(n)).compact
      end),
      Registration.new(names: %i[diff], opts: %i[ms], usage: '%{noun} diff <%{noun}-a> <%{noun}-b>  (each: %{noun} string or unix timestamp)',
                       missing: ->(args) { args[0].nil? || args[1].nil? },
                       run: ->(opts, _kind) { input(opts.args[0], opts).difference(input(opts.args[1], opts)).compact }),
    ].freeze

    def self.usage(registration, kind)
      text = registration.usage
      text = "%{noun} #{text}" unless text.start_with?('%{noun}')
      "usage: h #{format(text, noun: kind.noun)}"
    end

    def self.register(hiiro, kind_name)
      kind = KINDS.fetch(kind_name)
      hiiro.add_flag(:ms, short: :m, desc: 'Use milliseconds instead of seconds')
      hiiro.add_flag(:utc, short: :u, desc: 'Output in UTC')
      REGISTRATIONS.each do |registration|
        hiiro.add_cmd(*registration.names, opts: registration.opts || kind.now_opts) do
          abort TimeCommands.usage(registration, kind) if registration.missing&.call(@opts.args)
          puts registration.run.call(@opts, kind)
        end
      end
    end
  end
end
