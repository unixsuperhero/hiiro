require 'uri'

class Hiiro
  class Extractor
    Patterns = URI::REGEXP::PATTERN.constants.to_h { |k|
      re = URI::REGEXP::PATTERN.const_get(k)
      const_set(k, re)
      [k.to_s.downcase.to_sym, re]
    }

    def self.patterns
      Patterns
    end

    def self.all(input)
      Patterns.to_h { |k,v|
        pat = Regexp.new(v)
        [k, input.scan(pat)]
      }
    end
  end
end
