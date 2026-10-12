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

    State = Struct.new(:mode, :cursor, :top, :horizontal_offset, :query, :pick_query, :message, keyword_init: true)

    class Pane
      include Terminal

      attr_reader :width, :height

      def initialize(width:, height:)
        @width = width
        @height = height
      end

      def lines(texts)
        Array.new(height) { |idx| truncate(texts[idx].to_s, width).ljust(width) }
      end
    end

    class Screen
      include Terminal

      KEY_MAP = {
        'j' => :down, :down => :down,
        'k' => :up, :up => :up,
        'h' => :scroll_left, :left => :scroll_left,
        'l' => :scroll_right, :right => :scroll_right,
        '/' => :search,
        'q' => :quit, :escape => :quit, :ctrl_c => :quit,
      }.freeze

      BACKSPACES = ["\u007F", "\b"].freeze

      def self.key_map
        @key_map ||= KEY_MAP.dup
      end

      def self.inherited(subclass)
        super
        subclass.instance_variable_set(:@key_map, key_map.dup)
      end

      def self.key(key, action)
        key_map[key] = action
      end

      attr_reader :items, :state

      def initialize(items:, empty_message: 'No items.')
        @items = items
        @empty_message = empty_message
        @state = State.new(mode: :list, cursor: 0, top: 0, horizontal_offset: 0, query: '', pick_query: '', message: nil)
      end

      def cursor
        state.cursor
      end

      def top
        state.top
      end

      def horizontal_offset
        state.horizontal_offset
      end

      def message=(text)
        state.message = text
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
        catch(:tui_finish) do
          send(:"#{state.mode}_mode_key", key)
          :continue
        end
      end

      def frame(rows:, cols:)
        layout(rows, cols)[:lines]
      end

      def render
        cols = [terminal_cols - 1, 1].max
        out = layout(terminal_rows, cols)
        lines = out[:lines].each_with_index.map do |line, idx|
          padded = line.ljust(cols)
          next padded + "\e[K" unless idx == out[:current_row]

          "\e[7m#{padded[0, out[:list_width]]}\e[0m#{padded[out[:list_width]..]}\e[K"
        end

        $stdout.write("\e[H\e[2J")
        $stdout.write(lines.join("\r\n"))
        $stdout.write("\r")
        $stdout.flush
      end

      def header_lines
        []
      end

      def footer_lines
        [status_line]
      end

      def footer_height
        1
      end

      def detail_lines(_item)
        nil
      end

      def match?(item, query)
        item.to_s.downcase.include?(query.downcase)
      end

      def pick_trigger
        '@'
      end

      def pick_candidates
        []
      end

      def picked(_candidate)
      end

      def visible_items
        filtered_items
      end

      def current_item
        filtered_items[cursor]
      end

      def format_row(item, current, line_cols)
        prefix = current ? '> ' : '  '
        prefix + visible_text(item.to_s, [line_cols - prefix.length, 1].max, horizontal_offset)
      end

      def move(delta)
        state.cursor = (cursor + delta).clamp(0, [filtered_items.length - 1, 0].max)
        scroll_into_view(body_rows_budget)
        state.horizontal_offset = [horizontal_offset, max_horizontal_offset].min
      end

      def scroll_horizontal(delta)
        state.horizontal_offset = [[horizontal_offset + delta, 0].max, max_horizontal_offset].min
      end

      def body_rows_budget
        @body_rows || [terminal_rows - header_lines.length - footer_height, 1].max
      end

      def max_horizontal_offset(line_cols = nil, visible = nil)
        line_cols ||= [terminal_cols - 1, 1].max
        visible ||= window_items
        return 0 if visible.empty?

        longest_visible_item = visible.map { |item| item.to_s.length }.max || 0
        min_visible_chars = [5, line_cols].min

        [longest_visible_item - min_visible_chars, 0].max
      end

      def status_line
        case state.mode
        when :search then "/#{state.query}_"
        when :pick then pick_status
        else list_status
        end
      end

      private

      def down
        move(1)
      end

      def up
        move(-1)
      end

      def scroll_left
        scroll_horizontal(-4)
      end

      def scroll_right
        scroll_horizontal(4)
      end

      def search
        state.mode = :search
      end

      def quit
        finish(false)
      end

      def finish(value)
        throw :tui_finish, value
      end

      def list_mode_key(key)
        return state.mode = :pick if key == pick_trigger

        action = self.class.key_map[key]
        send(action) if action
      end

      def search_mode_key(key)
        return quit if key == :ctrl_c
        return state.mode = :list if key == :enter || key == :escape

        state.query = edit_text(state.query, key)
        move(0)
      end

      def pick_mode_key(key)
        return quit if key == :ctrl_c

        case key
        when :enter
          picked(pick_matches.first)
          leave_pick
        when :escape
          leave_pick
        else
          state.pick_query = edit_text(state.pick_query, key)
        end
      end

      def leave_pick
        state.pick_query = ''
        state.mode = :list
      end

      def edit_text(text, key)
        return text[0...-1] if BACKSPACES.include?(key)
        return text + key if key.is_a?(String) && key.length == 1 && key.ord >= 32

        text
      end

      def pick_matches
        prefix = state.pick_query.downcase
        pick_candidates.select { |candidate| candidate.to_s.downcase.start_with?(prefix) }
      end

      def pick_status
        labels = pick_matches.map { |candidate| "[#{candidate}]" }
        ["@#{state.pick_query}_", labels.join(' ')].reject(&:empty?).join('  ')
      end

      def list_status
        query = "/#{state.query}" unless state.query.empty?
        count = "#{filtered_items.empty? ? 0 : cursor + 1}/#{filtered_items.length}"
        [state.message, query, count].compact.join('  ')
      end

      def filtered_items
        return items if state.query.empty?

        items.select { |item| match?(item, state.query) }
      end

      def window_items
        filtered_items[top, body_rows_budget] || []
      end

      def scroll_into_view(rows)
        state.top = cursor if cursor < top
        state.top = cursor - rows + 1 if cursor >= top + rows
      end

      def layout(rows, cols)
        headers = header_lines
        @body_rows = [rows - headers.length - footer_height, 1].max
        move(0)

        item = current_item
        detail = item && detail_lines(item)
        list_width = detail ? [(cols - 1) / 2, 1].max : cols
        window = window_items
        state.horizontal_offset = [horizontal_offset, max_horizontal_offset(list_width, window)].min

        row_texts = window.each_with_index.map { |entry, idx| format_row(entry, top + idx == cursor, list_width) }
        row_texts = [@empty_message] if row_texts.empty?
        body = Pane.new(width: list_width, height: @body_rows).lines(row_texts)
        if detail
          right = Pane.new(width: [cols - list_width - 1, 0].max, height: @body_rows).lines(detail)
          body = body.zip(right).map { |left, text| "#{left}│#{text}" }
        end

        all = headers + body + footer_lines.first(footer_height)
        lines = Pane.new(width: cols, height: rows).lines(all).map(&:rstrip)
        current_row = item && headers.length + cursor - top

        { lines: lines, current_row: current_row, list_width: list_width }
      end
    end

    class ListScreen < Screen
      def visible_items
        window_items
      end

      def footer_lines
        return super unless state.mode == :list

        [state.message || "Showing #{top + 1}-#{top + visible_items.length} of #{items.length}"]
      end
    end
  end
end
