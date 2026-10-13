class Hiiro
  # Glob and extglob matching in Ruby, never through a shell. A pattern must
  # match the whole value. `/` separates segments:
  #
  #   *        any run of characters inside one segment
  #   ?        one character other than /
  #   [abc] [a-z] [!x] [^x]   one character from (or not from) the class, never /
  #   **/      zero or more whole segments ("**/*.bak" matches "a.bak" and "x/y/a.bak")
  #   **       anywhere else: any run of characters, / included
  #   \c       the character c literally
  #
  # With extglob, PATTERN-LIST is alternatives separated by | inside one segment:
  #
  #   ?(list) zero or one   *(list) zero or more   +(list) one or more
  #   @(list) exactly one   !(list) anything except one of them
  #
  # Matching is case-sensitive and dotfiles get no special treatment.
  class PathPattern
    class Invalid < StandardError; end

    def self.compile(pattern, extglob: false) = new(pattern, extglob: extglob)

    attr_reader :source

    def initialize(pattern, extglob: false)
      @source = pattern
      @extglob = extglob
      @nodes, rest = parse(pattern, 0, top: true)
      raise Invalid, "unexpected ) at #{rest + 1} in #{pattern.inspect}" if rest < pattern.length
    end

    def match?(value)
      @memo = {}
      matches?(@nodes, 0, value.to_s, 0)
    end

    private

    EXT_OPS = %w[? * + @ !].freeze

    def parse(text, index, top: false)
      nodes = []
      while index < text.length
        char = text[index]
        if @extglob && EXT_OPS.include?(char) && text[index + 1] == '('
          alternatives, index = parse_list(text, index + 2)
          nodes << [:ext, char, alternatives]
          next
        end
        if !top && (char == '|' || char == ')')
          return [nodes, index]
        end
        raise Invalid, "unexpected ) at #{index + 1} in #{text.inspect}" if char == ')' && @extglob && top

        case char
        when '\\'
          raise Invalid, "trailing \\ in #{text.inspect}" if index + 1 >= text.length
          nodes << [:char, text[index + 1]]
          index += 2
        when '*'
          if text[index + 1] == '*'
            if text[index + 2] == '/'
              nodes << [:dirs]
              index += 3
            else
              nodes << [:any_run]
              index += 2
            end
          else
            nodes << [:star]
            index += 1
          end
        when '?'
          nodes << [:one]
          index += 1
        when '['
          node, index = parse_class(text, index)
          nodes << node
        else
          raise Invalid, "/ inside an extglob list in #{text.inspect}" if char == '/' && !top
          nodes << [:char, char]
          index += 1
        end
      end
      raise Invalid, "unclosed ( in #{text.inspect}" unless top

      [nodes, index]
    end

    def parse_list(text, index)
      alternatives = []
      loop do
        raise Invalid, "unclosed ( in #{text.inspect}" if index >= text.length

        nodes, index = parse(text, index)
        raise Invalid, "unclosed ( in #{text.inspect}" if index >= text.length

        alternatives << nodes
        index += 1
        return [alternatives, index] if text[index - 1] == ')'
      end
    end

    def parse_class(text, index)
      close = index + 1
      close += 1 if %w[! ^].include?(text[close])
      close += 1 if text[close] == ']'
      close = text.index(']', close)
      return [[:char, '['], index + 1] unless close

      body = text[(index + 1)...close]
      negate = %w[! ^].include?(body[0])
      body = body[1..] if negate
      [[:class, negate, class_regexp(body)], close + 1]
    end

    def class_regexp(body)
      escaped = body.gsub(/[\\\]\[\^]/) { |c| "\\#{c}" }
      Regexp.new("[#{escaped}]")
    rescue RegexpError => error
      raise Invalid, "bad character class [#{body}]: #{error.message}"
    end

    def matches?(nodes, index, text, position)
      key = [nodes.object_id, index, text, position]
      return @memo[key] if @memo.key?(key)

      @memo[key] = compute(nodes, index, text, position)
    end

    def compute(nodes, index, text, position)
      return position == text.length if index == nodes.length

      node = nodes[index]
      case node[0]
      when :char
        text[position] == node[1] && matches?(nodes, index + 1, text, position + 1)
      when :one
        position < text.length && text[position] != '/' && matches?(nodes, index + 1, text, position + 1)
      when :class
        char = text[position]
        char && char != '/' && (node[2].match?(char) != node[1]) && matches?(nodes, index + 1, text, position + 1)
      when :star
        segment_ends(text, position).any? { |stop| matches?(nodes, index + 1, text, stop) }
      when :any_run
        (position..text.length).any? { |stop| matches?(nodes, index + 1, text, stop) }
      when :dirs
        directory_ends(text, position).any? { |stop| matches?(nodes, index + 1, text, stop) }
      when :ext
        segment_ends(text, position).any? do |stop|
          ext_match?(node[1], node[2], text[position...stop]) && matches?(nodes, index + 1, text, stop)
        end
      end
    end

    # Every stop from position up to the next / (or the end).
    def segment_ends(text, position)
      slash = text.index('/', position) || text.length
      (position..slash)
    end

    # position itself, then after each following /.
    def directory_ends(text, position)
      stops = [position]
      cursor = position
      while (slash = text.index('/', cursor))
        stops << slash + 1
        cursor = slash + 1
      end
      stops
    end

    def ext_match?(op, alternatives, piece)
      case op
      when '@' then one_of?(alternatives, piece)
      when '?' then piece.empty? || one_of?(alternatives, piece)
      when '+' then repeated?(alternatives, piece)
      when '*' then piece.empty? || repeated?(alternatives, piece)
      when '!' then !one_of?(alternatives, piece)
      end
    end

    def one_of?(alternatives, piece)
      alternatives.any? { |nodes| matches?(nodes, 0, piece, 0) }
    end

    def repeated?(alternatives, piece)
      return false if piece.empty?

      (1..piece.length).any? do |stop|
        one_of?(alternatives, piece[0...stop]) && (stop == piece.length || repeated?(alternatives, piece[stop..]))
      end
    end
  end
end
