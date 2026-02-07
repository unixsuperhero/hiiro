require 'open3'

class Hiiro
  class Sk
    def self.select(lines)
      input = lines.is_a?(Array) ? lines.join("\n") : lines.to_s
      selected, status = Open3.capture2('sk', stdin_data: input)

      return nil unless status.success?

      result = selected.strip
      return nil if result.empty?

      result
    end
  end
end
