require 'io/console'

class Hiiro
  module Tui
    module Terminal
      def with_screen
        input = $stdin
        $stdout.write("\e[?1049h\e[?25l")
        $stdout.flush

        input.raw do
          yield input
        end
      ensure
        $stdout.write("\r\e[0m\e[?25h\e[?1049l")
        $stdout.flush
      end

      def read_key(input)
        char = input.getch
        return :ctrl_c if char == "\u0003"
        return :enter if char == "\r" || char == "\n"

        if char == "\e"
          first = read_escape_char(input)
          return :escape if first.nil?
          return :escape unless first == '['

          case read_escape_char(input)
          when 'A' then :up
          when 'B' then :down
          when 'C' then :right
          when 'D' then :left
          else :escape
          end
        else
          char
        end
      end

      def read_escape_char(input)
        return nil unless IO.select([input], nil, nil, 0.02)

        input.getch
      end

      def terminal_rows
        env_dimension('LINES') || IO.console.winsize[0]
      rescue StandardError
        24
      end

      def terminal_cols
        env_dimension('COLUMNS') || IO.console.winsize[1]
      rescue StandardError
        80
      end

      def terminal_line(text, cols)
        truncate(text, cols) + "\e[K"
      end

      def center_text(text, cols)
        truncated = truncate(text, cols)
        return truncated if truncated.length >= cols

        left_padding = [(cols - truncated.length) / 2, 0].max
        (' ' * left_padding) + truncated
      end

      def truncate(text, cols)
        return text if text.length <= cols
        return text[0, cols] if cols <= 1

        text[0, cols - 1] + '…'
      end

      def visible_text(text, cols, offset = 0)
        return truncate(text, cols) if offset <= 0

        clipped = text[offset..] || ''
        return truncate(clipped, cols) if cols <= 1

        truncate("«#{clipped}", cols)
      end

      def env_dimension(name)
        value = ENV[name].to_i
        return nil unless value.positive?

        value
      end
    end

    class ListScreen
      include Terminal

      attr_reader :items, :cursor, :top, :horizontal_offset

      def initialize(items:, empty_message: 'No items.')
        @items = items
        @empty_message = empty_message
        @cursor = 0
        @top = 0
        @horizontal_offset = 0
      end

      def run
        if items.empty?
          puts @empty_message
          return false
        end

        with_screen do |input|
          loop do
            render

            result = handle_key(read_key(input))
            return result unless result == :continue
          end
        end
      end

      def handle_key(key)
        case key
        when :up, 'k'
          move(-1)
        when :down, 'j'
          move(1)
        when :left, 'h'
          scroll_horizontal(-4)
        when :right, 'l'
          scroll_horizontal(4)
        when 'q', :escape, :ctrl_c
          return false
        end

        :continue
      end

      def render
        rows = terminal_rows
        cols = terminal_cols
        line_cols = [cols - 1, 1].max
        headers = header_lines
        visible_rows = [rows - headers.length - footer_height, 1].max
        visible = items[@top, visible_rows] || []
        @horizontal_offset = [horizontal_offset, max_horizontal_offset(line_cols, visible)].min

        lines = headers.map { |line| terminal_line(line, line_cols) }
        visible.each_with_index do |item, idx|
          lines << format_row(item, @top + idx == cursor, line_cols)
        end

        (visible_rows - visible.length).times { lines << terminal_line('', line_cols) }
        footer_lines.each { |line| lines << terminal_line(line, line_cols) }

        $stdout.write("\e[H\e[2J")
        $stdout.write(lines.join("\r\n"))
        $stdout.write("\r")
        $stdout.flush
      end

      def header_lines
        []
      end

      def footer_lines
        ["Showing #{@top + 1}-#{@top + visible_items.length} of #{items.length}"]
      end

      def footer_height
        1
      end

      def format_row(item, current, line_cols)
        prefix = current ? '> ' : '  '
        style = current ? "\e[7m" : "\e[0m"
        text = (prefix + visible_text(item.to_s, [line_cols - prefix.length, 1].max, horizontal_offset)).ljust(line_cols)

        "#{style}#{text}\e[0m\e[K"
      end

      def move(delta)
        @cursor = [[cursor + delta, 0].max, items.length - 1].min
        visible_rows = body_rows_budget
        @top = cursor if cursor < top
        @top = cursor - visible_rows + 1 if cursor >= top + visible_rows
        @horizontal_offset = [horizontal_offset, max_horizontal_offset].min
      end

      def scroll_horizontal(delta)
        @horizontal_offset = [[horizontal_offset + delta, 0].max, max_horizontal_offset].min
      end

      def visible_items
        items[top, body_rows_budget] || []
      end

      def body_rows_budget
        [terminal_rows - header_lines.length - footer_height, 1].max
      end

      def max_horizontal_offset(line_cols = nil, visible = nil)
        line_cols ||= [terminal_cols - 1, 1].max
        visible ||= visible_items
        return 0 if visible.empty?

        longest_visible_item = visible.map { |item| item.to_s.length }.max || 0
        min_visible_chars = [5, line_cols].min

        [longest_visible_item - min_visible_chars, 0].max
      end
    end
  end
end
