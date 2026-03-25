class Hiiro
  class Options
    attr_reader :definitions

    def self.parse(args, &block)
      new(&block).parse!(args)
    end

    def self.setup(&block)
      new(&block)
    end

    # Support both: new(&block) for setup, or new(args, &block) for parse
    def self.new(args = nil, &block)
      instance = allocate
      instance.send(:base_initialize, &block)
      if args
        instance.parse!(args)
      else
        instance
      end
    end

    def initialize(&block)
      base_initialize(&block)
    end

    private def base_initialize(&block)
      @definitions = {}
      flag(:help, short: 'h', desc: 'Show this help message')
      instance_eval(&block) if block
    end

    def help_text
      lines = []
      @definitions.each do |name, defn|
        next if name == :help
        lines << defn.usage_line
      end
      lines << @definitions[:help].usage_line
      lines.join("\n")
    end

    def hint
      @definitions
        .reject { |k, _| k == :help }
        .map { |_, d| d.flag? ? d.long_form : "#{d.long_form} <val>" }
        .map { |s| "[#{s}]" }
        .join(' ')
    end

    def flag(name, long: nil, short: nil, default: false, desc: nil)
      defn = Definition.new(name, long: long, short: short, type: :flag, default: default, desc: desc)
      deconflict_short(short) if short
      @definitions[name.to_sym] = defn
      self
    end

    def option(name, long: nil, short: nil, type: :string, default: nil, desc: nil, multi: false, flag_ifs: [])
      defn = Definition.new(name, long: long, short: short, type: type, default: default, desc: desc, multi: multi, flag_ifs: Array(flag_ifs))
      deconflict_short(short) if short
      @definitions[name.to_sym] = defn
      self
    end

    private

    def deconflict_short(short)
      short_s = short.to_s
      @definitions.each_value { |d| d.short = nil if d.short == short_s }
    end

    public

    def select(names)
      subset = self.class.setup {}
      names.each do |name|
        defn = @definitions[name.to_sym]
        subset.definitions[name.to_sym] = defn if defn
      end
      subset
    end

    def parse(args)
      Args.new(@definitions, args.flatten.compact)
    end

    def parse!(args)
      parse(args)
    end

    class Args
      attr_reader :remaining_args, :original_args
      alias args remaining_args

      def initialize(definitions, raw_args)
        @definitions = definitions
        @original_args = raw_args.dup.freeze
        @values = {}
        @remaining_args = []
        do_parse(raw_args.dup)
      end

      def [](name)
        @values[name.to_sym]
      end

      def fetch(name, default = nil)
        key = name.to_sym
        return @values[key] if @values.key?(key)
        return yield if block_given?
        default
      end

      def uses_option?(name)
        key = name.to_sym
        return false unless @definitions.key?(key)
        @values[key] != @definitions[key].default
      end

      def help?
        @values[:help]
      end

      def help_text
        lines = []
        @definitions.each do |name, defn|
          next if name == :help
          lines << defn.usage_line
        end
        lines << @definitions[:help].usage_line
        lines.join("\n")
      end

      def to_h
        @values.dup
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

      def do_parse(args)
        @definitions.each do |name, defn|
          @values[name] = defn.multi ? [] : defn.default
        end

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
      end

      def parse_long_option(arg, args)
        parts     = arg.split('=', 2)
        flag_part = parts[0]
        value     = parts[1]

        defn = @definitions.values.find { |d| d.long_form == flag_part }
        return unless defn

        if defn.flag? || defn.flag_active?(@values)
          @values[defn.name] = !defn.default
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

          if defn.flag? || defn.flag_active?(@values)
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

    class Definition
      attr_reader :name, :long, :type, :default, :desc, :multi, :flag_ifs
      attr_accessor :short

      def initialize(name, short: nil, long: nil, type: :string, default: nil, desc: nil, multi: false, flag_ifs: [])
        @name = name.to_sym
        @short = short&.to_s
        @long = long&.to_sym
        @type = type
        @default = default
        @desc = desc
        @multi = multi
        @flag_ifs = flag_ifs.map(&:to_sym)
      end

      def flag_active?(values)
        @flag_ifs.any? { |f| values[f] }
      end

      def flag?
        type == :flag
      end

      def long_form
        "--#{(@long || @name).to_s.tr('_', '-')}"
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

      def usage_line
        parts = []
        parts << (short_form ? "#{short_form}, #{long_form}" : "    #{long_form}")
        parts[0] = parts[0].ljust(20)
        parts << value_hint unless flag?
        parts << desc if desc
        parts << "(default: #{default.inspect})" if default && !flag?
        parts << "[multi]" if multi
        parts.join("  ")
      end

      def value_hint
        case type
        when :integer then "<int>"
        when :float then "<num>"
        else "<value>"
        end
      end
    end
  end
end
