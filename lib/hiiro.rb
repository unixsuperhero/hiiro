require "fileutils"
require "yaml"

require_relative "hiiro/version"

class Hiiro
  def self.init(*args, plugins: [], logging: false, **values, &block)
    load_env
    args = ARGV if args.empty?

    new($0, *args, logging: logging, **values).tap do |hiiro|
      hiiro.load_plugins(*plugins)

      hiiro.add_subcmd(:edit, **values) { |*args|
        system(ENV['EDITOR'] || 'nvim', hiiro.bin)
      }

      block.call(hiiro) if block
    end
  end

  def self.load_env
    Config.plugin_files.each do |plugin_file|
      require plugin_file
    end

    self
  end

  attr_reader :bin, :bin_name, :all_args
  attr_reader :subcmd, :args
  attr_reader :loaded_plugins
  attr_reader :logging
  attr_reader :global_values

  def initialize(bin, *args, logging: false, **values)
    @bin = bin
    @bin_name = File.basename(bin)
    @all_args = args
    @subcmd, *@args = args # normally i would never do this
    @loaded_plugins = []
    @logging = logging
    @global_values = values
  end

  def run
    result = runner.run(*args)

    handle_result(result)

    exit 1
  rescue => e
    puts "ERROR: #{e.message}"
    puts e.backtrace
    exit 1
  end

  def handle_result(result)
    exit 0 if result.nil? || result

    exit 1
  end

  def runnable?
    runner
  end

  def runner
    runners.runner || runners.default_subcommand
  end

  def runners
    @runners ||= Runners.new(self)
  end

  def add_default(**values, &handler)
    runners.add_default(handler, **global_values, **values)
  end

  def add_subcommand(name, **values, &handler)
    runners.add_subcommand(name, handler, **global_values, **values)
  end
  alias add_subcmd add_subcommand

  def full_name
    runner&.full_name || [bin_name, subcmd].join(?-)
  end

  def subcommand_names
    runners.subcommand_names
  end

  def pins = @pins ||= Pin.new(self)

  def load_plugins(*plugins)
    plugins.flatten.each { |plugin| load_plugin(plugin) }
  end

  def load_plugin(plugin_const)
    return if @loaded_plugins.include?(plugin_const)

    plugin_const.load(self)
    @loaded_plugins.push(plugin_const)
  end

  def help
    ambiguous = runners.ambiguous_matches

    if ambiguous.any?
      puts "Ambiguous subcommand #{subcmd.inspect}!"
      puts ""
      puts "Did you mean one of these?"
      list_runners(ambiguous)
    else
      subcmd_msg = "Subcommand required!"
      subcmd_msg = "Subcommand #{subcmd.inspect} not found!" if subcmd

      puts subcmd_msg
      puts ""
      puts "Possible subcommands:"
      list_runners(runners.all_runners)
    end
  end

  def list_runners(list)
    max_name = list.map { |r| r.subcommand_name.length }.max || 0
    max_type = list.map { |r| r.type.to_s.length }.max || 0
    max_params = list.map { |r| r.params_string.to_s.length }.max || 0

    list.each do |r|
      name = r.subcommand_name.ljust(max_name)
      type = "(#{r.type})".ljust(max_type + 2)
      params = r.params_string
      params_col = params ? params.ljust(max_params) : ''.ljust(max_params)
      location = r.location
      puts "  #{name}  #{params_col}  #{type}  #{location}"
    end
  end

  def log(message)
    return unless logging

    puts "[Hiiro: #{bin_name} #{(runner&.subcommand_name || subcmd).inspect}]: #{message}"
  end

  def parsed_args
    i = Args.new(*args)
  end

  def get_value(name)
    runner&.values&.[](name)
  end

  class Config
    class << self
      def plugin_files
        Dir.glob(File.join(plugin_dir, '*'))
      end

      def plugin_dir
        config_dir('plugins')
      end

      def config_dir(subdir=nil)
        File.join(Dir.home, '.config/hiiro', *[subdir].compact).tap do |config_path|
          FileUtils.mkdir_p(config_path) unless Dir.exist?(config_path)
        end
      end
    end
  end

  def default_subcommand
    Runners::Subcommand.new(
      bin_name,
      :DEFAULT,
      lambda { help; false },
    )
  end

  class Runners
    attr_reader :hiiro, :bin_name, :subcmd, :subcommands

    def initialize(hiiro)
      @hiiro = hiiro
      @bin_name = hiiro.bin_name
      @subcmd = hiiro.subcmd
      @subcommands = {}
      @default_subcommand = hiiro.default_subcommand
    end

    def add_default(handler, **values)
      @default_subcommand = Subcommand.new(
        bin_name,
        :DEFAULT,
        handler,
        **values
      )
    end

    def runner
      return exact_runner if exact_runner
      return unambiguous_runner if unambiguous_runner

      @default_subcommand
    end

    def subcommand_names
      all_runners.map(&:subcommand_name)
    end

    def all_runners
      [*all_bins, *subcommands.values]
    end

    def paths
      @paths ||= ENV['PATH'].split(?:).uniq
    end

    def all_bins
      pattern = format('{%s}/%s-*', paths.join(?,), bin_name)

      Dir.glob(pattern).map { |path| Bin.new(bin_name, path) }
    end

    def add_subcommand(name, handler, **values)
      @subcommands[name] = Subcommand.new(bin_name, name, handler, values)
    end

    def exact_runner
      all_runners.find { |r| r.exact_match?(subcmd) }
    end

    def unambiguous_runner
      return nil if subcmd.nil?

      matches = matching_runners
      return matches.first if matches.count == 1

      nil
    end

    def ambiguous_matches
      return [] if subcmd.nil?

      matches = matching_runners
      return matches if matches.count > 1

      []
    end

    def matching_runners
      remove_child_runners(all_matching_runners)
    end

    def all_matching_runners
      all_runners.select { |r| r.match?(subcmd) }
    end

    def remove_child_runners(list)
      list.reject do |r|
        list.any? { |other| r != other && r.full_name.start_with?(other.full_name + ?-) }
      end
    end

    class Bin
      attr_reader :bin_name, :path, :name
      alias full_name name

      def initialize(bin_name, path)
        @bin_name = bin_name
        @path = path
        @name = File.basename(path)
      end

      def run(*args)
        system(path, *args)
      end

      def exact_match?(subcmd)
        subcommand_name == subcmd.to_s
      end

      def match?(subcmd)
        subcommand_name.start_with?(subcmd.to_s)
      end

      def subcommand_name
        name.sub("#{bin_name}-", '')
      end

      def values
        {}
      end

      def type
        :bin
      end

      def location
        path
      end

      def params_string
        nil
      end
    end

    class Subcommand
      attr_reader :bin_name, :name, :handler, :values
      alias subcommand_name name

      def initialize(bin_name, name, handler, values={})
        @bin_name = bin_name
        @name = name.to_s
        @handler = handler
        @values = values || {}
      end

      def run(*args)
        handler.call(*args)
      end

      def exact_match?(subcmd)
        name == subcmd.to_s
      end

      def match?(subcmd)
        name.start_with?(subcmd.to_s)
      end

      def full_name
        [bin_name, name].join(?-)
      end

      def type
        :subcommand
      end

      def location
        handler.source_location&.join(':')
      end

      def params_string
        return nil unless handler.respond_to?(:parameters)

        params = handler.parameters
        return nil if params.empty?
        return nil if params == [[:rest]] || params == [[:rest, :args]]

        params.map { |type, name|
          case type
          when :req then "<#{name}>"
          when :opt then "[#{name}]"
          when :rest then "[*#{name}]" if name
          when :keyreq then "<#{name}:>"
          when :key then "[#{name}:]"
          when :keyrest then "[**#{name}]" if name
          when :block then "[&#{name}]" if name
          end
        }.compact.join(' ')
      end
    end
  end

  class Args
    attr_reader :raw_args

    def initialize(*raw_args)
      @raw_args = raw_args
    end

    def flags
      @flags ||= proc {
        raw_args.select { |arg|
          arg.match?(/^-[^-]/)
        }.flat_map { |arg|
          arg.sub(/^-/, '').chars
        }
      }.call
    end

    def flag?(flag)
      flags.include?(flag)
    end

    def flag_value(flag)
      found_flag = false
      raw_args.each do |arg|
        if found_flag
          return arg
        end

        if arg.match?(/^-\w*#{flag}/)
          found_flag = true
        end
      end

      nil
    end

    def values
      raw_args.reject do |arg|
        arg.match?(/^-/)
      end
    end
  end

  load_env
end
