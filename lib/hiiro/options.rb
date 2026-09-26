class Hiiro
  # The declared options of a command: definitions plus mutual-exclusion groups.
  # Answers help/hint text, token lookup, defaults, and conflicts for both the
  # declaring side (Options) and the parsed side (Options::Args).
  class OptionSet
    attr_reader :definitions, :mutex_groups

    def initialize(definitions, mutex_groups: [])
      @definitions = definitions
      @mutex_groups = mutex_groups
    end

    def help_text
      lines = definitions.reject { |name, _| name == :help }.map { |_, defn| defn.usage_line }
      lines << definitions[:help].usage_line
      lines.join("\n")
    end

    def hint
      definitions
        .reject { |k, _| k == :help }
        .map { |_, d| d.flag? ? d.long_form : "#{d.long_form} <val>" }
        .map { |s| "[#{s}]" }
        .join(' ')
    end

    # '--name' | '-n' | :name → Definition or nil
    def definition_for(token)
      text = token.to_s
      if text.start_with?('--')
        definitions.values.find { |d| d.long_form == text }
      elsif text.start_with?('-') && text.length == 2
        definitions.values.find { |d| d.short == text[1] }
      else
        definitions[text.to_sym]
      end
    end

    def defaults
      definitions.to_h { |name, defn| [name, defn.multi ? [] : defn.default] }
    end

    def subset(names)
      self.class.new(definitions.slice(*names.map(&:to_sym)), mutex_groups: mutex_groups)
    end

    # Names reset when `name` is set. Star topology: the hub clears its spokes,
    # a spoke clears only the hub.
    def conflicts_for(name)
      mutex_groups.select { |group| group.include?(name) }.flat_map do |hub, *spokes|
        name == hub ? spokes : [hub]
      end
    end
  end

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

    def option_set
      OptionSet.new(@definitions, mutex_groups: @mutex_groups || [])
    end

    def help_text = option_set.help_text
    def hint      = option_set.hint

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

    # Declare a mutual exclusion group with star topology.
    # The first name is the hub; the rest are spokes.
    #   Setting the hub   clears all spokes.
    #   Setting a spoke   clears only the hub.
    #   Spokes can still be combined with each other freely.
    # Two-member groups are fully symmetric (hub == spoke).
    # Last flag encountered in argv always wins.
    def mutual_exclusion(*names)
      @mutex_groups ||= []
      @mutex_groups << names.map(&:to_sym)
      self
    end

    private

    def deconflict_short(short)
      short_s = short.to_s
      @definitions.each_value { |d| d.short = nil if d.short == short_s }
    end

    public

    def select(names)
      names = names.map(&:to_sym).uniq
      subset = self.class.setup {}
      reserved_shorts = ['h'] + names.filter_map { |name| @definitions[name]&.short }
      auto_shorts = names.reject { |name| @definitions.key?(name) }.map { |name| name.to_s[0] }.tally
      names.each do |name|
        defn = @definitions[name]
        if defn
          subset.definitions[name] = defn
        else
          short = name.to_s[0]
          short = nil if reserved_shorts.include?(short) || auto_shorts[short] > 1
          subset.flag(name, short: short, desc: "auto-created flag: #{name}")
        end
      end
      subset
    end

    def parse(args)
      Args.new(option_set, args.flatten.compact)
    end

    def parse!(args)
      parse(args)
    end

    class Args
      attr_reader :remaining_args, :original_args
      alias args remaining_args

      def initialize(option_set, raw_args)
        @option_set = option_set
        @definitions = option_set.definitions
        @original_args = raw_args.dup.freeze
        @values = {}
        @remaining_args = []
        do_parse(raw_args.dup)
      end

      def files = @files ||= args.select{|x| File.file?(x) }
      def dirs = @dirs ||= args.select{|x| File.directory?(x) }
      def file_or_dirs = @file_or_dirs ||= args.select{|x| File.file?(x) || File.directory?(x) }
      def not_files = args - files
      def not_file_or_dirs = args - file_or_dirs

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

      def help_text = @option_set.help_text

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
        @values = @option_set.defaults

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

        defn = @option_set.definition_for(flag_part)
        return unless defn

        if defn.flag? || defn.flag_active?(@values)
          set_flag(defn, !defn.default)
        else
          value ||= args.shift
          store_value(defn, value)
        end
      end

      def parse_short_options(arg, args)
        chars = arg.sub(/^-/, '').chars

        unless chars.any? { |c| @option_set.definition_for("-#{c}") }
          @remaining_args << arg
          return
        end

        chars.each_with_index do |char, idx|
          defn = @option_set.definition_for("-#{char}")
          next unless defn

          if defn.flag? || defn.flag_active?(@values)
            set_flag(defn, !defn.default)
          elsif idx == chars.length - 1
            store_value(defn, args.shift)
          else
            store_value(defn, chars[(idx + 1)..].join)
            break
          end
        end
      end

      def set_flag(defn, value)
        # Star topology: group[0] is the hub.
        #   Setting the hub   → clears all spokes (group[1..])
        #   Setting a spoke   → clears only the hub (group[0])
        # This lets spokes coexist with each other (e.g. --red --drafts is fine)
        # while still preventing any spoke from combining with the hub (--all).
        @option_set.conflicts_for(defn.name).each do |other|
          other_defn = @definitions[other]
          @values[other] = other_defn.default if other_defn
        end
        @values[defn.name] = value
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
