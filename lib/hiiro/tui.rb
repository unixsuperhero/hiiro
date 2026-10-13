require 'io/console'

class Hiiro
  module Tui
    module Terminal
      CSI_KEYS = { 'A' => :up, 'B' => :down, 'C' => :right, 'D' => :left, 'H' => :home, 'F' => :end }.freeze
      TILDE_KEYS = { '1' => :home, '4' => :end, '3' => :delete }.freeze

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
        return :tab if char == "\t"
        return :ctrl_u if char == "\u0015"
        return char unless char == "\e"
        return :escape unless read_escape_char(input) == '['

        csi_key(input)
      end

      def csi_key(input)
        char = read_escape_char(input)
        return CSI_KEYS[char] if CSI_KEYS.key?(char)
        return :escape unless char&.match?(/\A\d\z/) && read_escape_char(input) == '~'

        TILDE_KEYS.fetch(char, :escape)
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

    State = Struct.new(:mode, :cursor, :top, :horizontal_offset, :query, :message, :prompt_label, :prompt_text, keyword_init: true)

    module Fuzzy
      WORD_BREAKS = "-_/. ".freeze

      module_function

      def rank(candidates, query)
        return candidates if query.empty?

        scored = candidates.each_with_index.filter_map do |candidate, idx|
          score = score(candidate, query)
          [score, candidate.length, candidate, idx] if score
        end
        scored.sort.map { |entry| entry[2] }
      end

      def score(candidate, query)
        text = candidate.downcase
        query = query.downcase
        return 0 if text.start_with?(query)
        return 1 if text.include?(query)
        return 2 if word_starts(text, query[0]).any? { |idx| subsequence?(text[idx + 1..], query[1..]) }

        gaps = subsequence_gaps(text, query)
        gaps && 3 + gaps
      end

      def word_starts(text, char)
        (0...text.length).select { |idx| text[idx] == char && (idx.zero? || WORD_BREAKS.include?(text[idx - 1])) }
      end

      def subsequence?(text, query)
        !subsequence_gaps(text, query).nil?
      end

      def subsequence_gaps(text, query)
        gaps = 0
        last = nil
        query.each_char do |char|
          idx = text.index(char, last ? last + 1 : 0)
          return nil unless idx

          gaps += 1 if last && idx != last + 1
          last = idx
        end
        gaps
      end
    end

    # The text of one open prompt: a cursor, editing keys, and completion from a trigger table
    # ({ '@' => source } completes a word starting with '@'; { '' => source } the word at the cursor).
    class LineEditor
      attr_reader :text, :cursor, :selected

      def initialize(text: '', triggers: {})
        @text = text.to_s
        @cursor = @text.length
        @selected = 0
        @triggers = triggers
        @pool = {}
      end

      def insert(char)
        edit do
          @text = @text[0, cursor] + char + @text[cursor..]
          @cursor += char.length
        end
      end

      def backspace
        return if cursor.zero?

        edit do
          @text = @text[0, cursor - 1] + @text[cursor..]
          @cursor -= 1
        end
      end

      def delete = edit { @text = @text[0, cursor] + @text[cursor + 1..].to_s }
      def left = edit { @cursor = [cursor - 1, 0].max }
      def right = edit { @cursor = [cursor + 1, text.length].min }
      def home = edit { @cursor = 0 }
      def end_of_line = edit { @cursor = text.length }

      def kill_line
        edit do
          @text = ''
          @cursor = 0
        end
      end

      def token
        start = (text[0, cursor].rindex(' ') || -1) + 1
        word = text[start...cursor]
        return { start:, trigger: word[0], query: word[1..] } if !word.empty? && @triggers.key?(word[0])
        return { start:, trigger: '', query: word } if @triggers.key?('')

        nil
      end

      def choices(limit: 8)
        found = token
        return [] unless found

        ranked = Fuzzy.rank(pool(found[:trigger]), found[:query]).first(limit)
        ranked.first == found[:query] ? [] : ranked
      end

      def select(delta)
        count = choices.length
        @selected = (selected + delta) % count unless count.zero?
      end

      def accept
        found = token
        choice = choices[selected]
        return false unless choice

        replacement = found[:trigger] + choice + (found[:trigger].empty? ? '' : ' ')
        edit do
          @text = @text[0, found[:start]] + replacement + @text[cursor..]
          @cursor = found[:start] + replacement.length
        end
        true
      end

      private

      def edit
        yield
        @selected = 0
      end

      def pool(trigger)
        @pool[trigger] ||= @triggers.fetch(trigger).call.to_a
      end
    end

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

      PROMPT_KEYS = {
        :delete => [:delete], :left => [:left], :right => [:right],
        :home => [:home], :end => [:end_of_line], :ctrl_u => [:kill_line],
        :up => [:select, -1], :down => [:select, 1],
        :tab => [:accept], :enter => [:accept],
      }.freeze

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
        @state = State.new(mode: :list, cursor: 0, top: 0, horizontal_offset: 0, query: '', message: nil, prompt_label: '', prompt_text: '')
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

      # Called from list mode for a key the key map does not bind.
      def unhandled_key(_key)
      end

      # Reads one line in the status line; Enter calls the block with the text,
      # Escape drops it. The block runs after the prompt closes, so it may prompt again.
      # `complete` is the LineEditor trigger table; Enter accepts an open choice before it submits.
      def prompt(label, default: '', complete: {}, &on_submit)
        state.prompt_label = label
        @editor = LineEditor.new(text: default, triggers: complete)
        state.prompt_text = @editor.text
        @on_prompt_submit = on_submit
        state.mode = :prompt
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
        when :prompt then prompt_status
        else list_status
        end
      end

      def prompt_status
        line = "#{state.prompt_label}: #{@editor.text[0, @editor.cursor]}_#{@editor.text[@editor.cursor..]}"
        choices = @editor.choices
        return line if choices.empty?

        found = @editor.token
        listed = choices.each_with_index.map { |choice, idx| idx == @editor.selected ? "[#{choice}]" : choice }
        "#{line}  #{["#{found[:trigger]}#{found[:query]}", '▸'].reject(&:empty?).join(' ')} #{listed.join(' ')}"
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
        action = self.class.key_map[key]
        action ? send(action) : unhandled_key(key)
      end

      def search_mode_key(key)
        return quit if key == :ctrl_c
        return state.mode = :list if key == :enter || key == :escape

        state.query = edit_text(state.query, key)
        move(0)
      end

      def prompt_mode_key(key)
        return quit if key == :ctrl_c
        return leave_prompt if key == :escape
        return submit_prompt if key == :enter && @editor.choices.empty?

        edit_prompt(key)
        state.prompt_text = @editor.text
      end

      def edit_prompt(key)
        if BACKSPACES.include?(key)
          @editor.backspace
        elsif PROMPT_KEYS.key?(key)
          @editor.public_send(*PROMPT_KEYS[key])
        elsif key.is_a?(String) && key.length == 1 && key.ord >= 32
          @editor.insert(key)
        end
      end

      def submit_prompt
        on_submit = @on_prompt_submit
        text = @editor.text
        leave_prompt
        on_submit&.call(text)
      end

      def leave_prompt
        @on_prompt_submit = nil
        @editor = nil
        state.prompt_label = ''
        state.prompt_text = ''
        state.mode = :list
      end

      def edit_text(text, key)
        return text[0...-1] if BACKSPACES.include?(key)
        return text + key if key.is_a?(String) && key.length == 1 && key.ord >= 32

        text
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
