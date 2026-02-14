require 'open3'
require_relative 'shell'

class Hiiro
  class Sk
    def self.select(lines)
      Shell.pipe_lines(lines, 'sk')
    end

    def self.map_select(mapping)
      keys = mapping.keys

      key = select(keys)

      mapping[key.to_s.chomp]
    end
  end
end
