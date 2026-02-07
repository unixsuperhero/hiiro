class Hiiro
  class Options
    class Definition
      attr_reader :name, :short, :type, :default, :desc, :multi

      def initialize(name, short: nil, type: :string, default: nil, desc: nil, multi: false)
        @name = name.to_sym
        @short = short&.to_s
        @type = type
        @default = default
        @desc = desc
        @multi = multi
      end

      def flag?
        type == :flag
      end

      def long_form
        "--#{name.to_s.tr('_', '-')}"
      end

      def short_form
        short ? "-#{short}" : nil
      end

      def match?(arg)
        arg == long_form || arg == short_form
      end

      def coerce(value)
        case type
        when :integer then value.to_i
        when :float then value.to_f
        else value
        end
      end
    end

    attr_reader :definitions, :values, :remaining_args
    alias args remaining_args

    def initialize(raw_args = [], &block)
      @raw_args = raw_args.dup
      @definitions = {}
      @values = {}
      @remaining_args = []
      @parsed = false

      instance_eval(&block) if block
      parse! if block
    end

    # DSL: define a toggle flag (default false, presence inverts)
    def flag(name, short: nil, default: false, desc: nil)
      defn = Definition.new(name, short: short, type: :flag, default: default, desc: desc)
      @definitions[name.to_sym] = defn
      self
    end

    # DSL: define an option that takes a value
    def option(name, short: nil, type: :string, default: nil, desc: nil, multi: false)
      defn = Definition.new(name, short: short, type: type, default: default, desc: desc, multi: multi)
      @definitions[name.to_sym] = defn
      self
    end

    def parse!
      return self if @parsed

      @definitions.each do |name, defn|
        @values[name] = defn.multi ? [] : defn.default
      end

      args = @raw_args.dup
      while args.any?
        arg = args.shift

        if arg == '--'
          @remaining_args.concat(args)
          break
        elsif arg.start_with?('--')
          parse_long_option(arg, args)
        elsif arg.start_with?('-') && arg.length > 1
          parse_short_options(arg, args)
        else
          @remaining_args << arg
        end
      end

      @parsed = true
      self
    end

    def [](name)
      @values[name.to_sym]
    end

    def method_missing(name, *args, &block)
      name_str = name.to_s
      if name_str.end_with?('?')
        key = name_str.chomp('?').to_sym
        return !!@values[key] if @definitions.key?(key)
      else
        return @values[name] if @definitions.key?(name)
      end
      super
    end

    def respond_to_missing?(name, include_private = false)
      key = name.to_s.chomp('?').to_sym
      @definitions.key?(key) || super
    end

    def to_h
      @values.dup
    end

    private

    def parse_long_option(arg, args)
      if arg.include?('=')
        opt, value = arg.split('=', 2)
        name = opt.sub(/^--/, '').tr('-', '_').to_sym
      else
        name = arg.sub(/^--/, '').tr('-', '_').to_sym
        value = nil
      end

      defn = @definitions[name]
      return unless defn

      if defn.flag?
        @values[name] = !defn.default
      else
        value ||= args.shift
        store_value(defn, value)
      end
    end

    def parse_short_options(arg, args)
      chars = arg.sub(/^-/, '').chars

      chars.each_with_index do |char, idx|
        defn = @definitions.values.find { |d| d.short == char }
        next unless defn

        if defn.flag?
          @values[defn.name] = !defn.default
        elsif idx == chars.length - 1
          store_value(defn, args.shift)
        else
          store_value(defn, chars[(idx + 1)..].join)
          break
        end
      end
    end

    def store_value(defn, value)
      coerced = defn.coerce(value)
      if defn.multi
        @values[defn.name] << coerced
      else
        @values[defn.name] = coerced
      end
    end
  end
end
