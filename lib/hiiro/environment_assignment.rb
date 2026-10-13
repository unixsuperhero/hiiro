class Hiiro
  # One `export NAME="VALUE"` line appended to a shell file. The value is a
  # literal: `"`, `\`, `$`, and backticks are escaped so sourcing the file never
  # evaluates it. `h env add` and `h export add` both write through this.
  #
  #   a = EnvironmentAssignment.new('GREETING', 'say "$HOME"')
  #   a.line                                   # => "export GREETING=\"say \\\"\\$HOME\\\"\"\n"
  #   EnvironmentAssignment.destination(home: '/h')            # => '/h/.zshenv.d/vars.zsh' if a file, else '/h/.zshenv'
  #   EnvironmentAssignment.destination(home: '/h', file: 'x') # => File.expand_path('x')
  #   a.append_to(path)                        # => path (keeps existing bytes and mode; new files are 0600)
  class EnvironmentAssignment
    NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    attr_reader :name, :value

    def self.destination(home:, file: nil)
      return File.expand_path(file) if file && !file.empty?

      module_file = File.join(home, '.zshenv.d', 'vars.zsh')
      File.file?(module_file) ? module_file : File.join(home, '.zshenv')
    end

    def initialize(name, value)
      raise Error, 'Invalid environment variable name' unless NAME.match?(name.to_s)
      raise Error, 'Environment variable value cannot contain a newline' if value.include?("\n")

      @name = name
      @value = value
    end

    def line
      escaped = value.gsub(/["\\$`]/) { |char| "\\#{char}" }
      "export #{name}=\"#{escaped}\"\n"
    end

    def append_to(path)
      File.open(path, 'a+', 0o600) do |file|
        unless file.size.zero?
          file.seek(-1, IO::SEEK_END)
          file.write("\n") unless file.read(1) == "\n"
        end
        file.write(line)
      end
      path
    end

    # The `add` registration over this writer. `words: true` joins every word
    # after NAME with single spaces into one literal value (`h export add`).
    def self.register(hiiro, usage:, words: false)
      hiiro.add_option :file, desc: 'Append to this file instead of ~/.zshenv.d/vars.zsh or ~/.zshenv'
      hiiro.add_cmd :add, args: words ? %w[NAME WORDS...] : %w[NAME VALUE], opts: [:file] do
        count = opts.args.length
        abort usage unless words ? count >= 2 : count == 2
        name, *rest = opts.args
        path = EnvironmentAssignment.destination(home: Dir.home, file: opts.file)
        EnvironmentAssignment.new(name, rest.join(' ')).append_to(path)
        puts "Added environment variable to #{path}"
      rescue Error, SystemCallError => e
        abort e.message
      end
    end
  end
end
