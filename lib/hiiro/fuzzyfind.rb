require_relative 'fuzzyfind/sk'
require_relative 'fuzzyfind/fzf'
require_relative 'shell'

class Hiiro
  class Fuzzyfind
    TOOLS = %w[sk fzf]

    def self.tool
      TOOLS.find { |name| system("command -v #{name} 2>/dev/null") }
    end

    def self.tool!
      match = tool

      return match if match

      puts "ERROR: No fuzzyfinder found!"
      exit 1
    end

    def self.select(lines)
      Shell.pipe_lines(lines, tool!)
    end

    def self.map_select(mapping)
      keys = mapping.keys

      key = select(keys)

      mapping[key.to_s.chomp]
    end
  end
end
