require_relative 'shell'

class Hiiro
  class Fuzzyfind
    TOOLS = %w[sk fzf]

    def self.tool
      TOOLS.find { |name| system("command -v #{name} &>/dev/null") }
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

    # Index of the chosen label, or nil when cancelled. Rows go to the finder
    # as "N<TAB>label" with only the label shown, so equal labels stay distinct
    # and nothing is recovered by parsing the label.
    def self.select_index(labels)
      rows = labels.each_with_index.map { |label, index| "#{index + 1}\t#{label.to_s.tr("\t\n", '  ')}" }
      chosen = Shell.pipe_lines(rows, tool!, '--delimiter', "\t", '--with-nth', '2..')
      number = chosen.to_s[/\A(\d+)\t/, 1]
      number && number.to_i.between?(1, labels.length) ? number.to_i - 1 : nil
    end

    def self.map_select(mapping)
      keys = mapping.keys

      key = select(keys)

      mapping[key.to_s.chomp]
    end
  end
end
