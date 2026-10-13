require "test_helper"
require "hiiro/tui"

class TuiTest < Minitest::Test
  FRUITS = %w[apple banana cherry jellybean kiwi lemon].freeze

  class FruitScreen < Hiiro::Tui::Screen
    def header_lines
      ['Fruits']
    end
  end

  class CompleteScreen < FruitScreen
    key 't', :ask_todo
    key 'f', :ask_table

    attr_reader :answers

    def initialize(**kwargs)
      super
      @answers = []
    end

    def ask_todo
      prompt('todo', complete: { '@' => -> { %w[hiiro hiiro-config rehiiro] } }) { |text| @answers << text }
    end

    def ask_table
      prompt('table', complete: { '' => -> { %w[link project sha sound t] } }) { |text| @answers << text }
    end
  end

  class FakeInput
    def initialize(text) = @chars = text.chars

    def getch = @chars.shift
  end

  class KeyReader
    include Hiiro::Tui::Terminal

    def read_escape_char(input) = input.getch
  end

  class CustomKeyScreen < FruitScreen
    key 'x', :custom

    def custom
      self.message = "custom on #{current_item}"
    end
  end

  class DetailScreen < FruitScreen
    def detail_lines(item)
      ["name: #{item}", "length: #{item.length}"]
    end
  end

  class PromptScreen < FruitScreen
    key 'n', :ask_name
    key 'c', :ask_chain

    attr_reader :answers, :unhandled

    def initialize(**kwargs)
      super
      @answers = []
      @unhandled = []
    end

    def ask_name
      prompt('name') { |text| @answers << text }
    end

    def ask_chain
      prompt('first', default: 'x') do |first|
        prompt('second') { |second| @answers << [first, second] }
      end
    end

    def unhandled_key(key)
      @unhandled << key
    end
  end

  def setup
    @saved_env = ENV.to_h.slice('LINES', 'COLUMNS')
    ENV['LINES'] = '8'
    ENV['COLUMNS'] = '40'
  end

  def teardown
    %w[LINES COLUMNS].each { |name| ENV[name] = @saved_env[name] }
  end

  def press(screen, *keys)
    keys.map { |key| screen.handle_key(key) }
  end

  def frame(screen)
    screen.frame(rows: 8, cols: 40)
  end

  def test_pane_pads_and_truncates_to_exact_rectangle
    pane = Hiiro::Tui::Pane.new(width: 5, height: 3)

    assert_equal ["abc  ", "abcd…", "     "], pane.lines(["abc", "abcdefgh"])
    assert_equal ["ab   ", "c    "], Hiiro::Tui::Pane.new(width: 5, height: 2).lines(["ab", "c", "d"])
  end

  def test_initial_frame_has_header_list_and_status
    screen = FruitScreen.new(items: FRUITS)

    assert_equal [
      "Fruits",
      "> apple",
      "  banana",
      "  cherry",
      "  jellybean",
      "  kiwi",
      "  lemon",
      "1/6",
    ], frame(screen)
  end

  def test_j_three_times_moves_the_marker
    screen = FruitScreen.new(items: FRUITS)

    assert_equal [:continue] * 3, press(screen, 'j', 'j', 'j')
    assert_equal [
      "Fruits",
      "  apple",
      "  banana",
      "  cherry",
      "> jellybean",
      "  kiwi",
      "  lemon",
      "4/6",
    ], frame(screen)
  end

  def test_cursor_scrolls_into_view_past_the_last_body_row
    screen = FruitScreen.new(items: FRUITS + %w[mango])

    press(screen, *(['j'] * 6))

    assert_equal [
      "Fruits",
      "  banana",
      "  cherry",
      "  jellybean",
      "  kiwi",
      "  lemon",
      "> mango",
      "7/7",
    ], frame(screen)
  end

  def test_search_filters_rows_and_keeps_query_after_enter
    screen = FruitScreen.new(items: FRUITS)
    press(screen, 'j', 'j', '/', 'j', 'e', 'l')

    assert_equal :search, screen.state.mode
    assert_equal [
      "Fruits",
      "> jellybean",
      "",
      "",
      "",
      "",
      "",
      "/jel_",
    ], frame(screen)

    press(screen, :enter)

    assert_equal :list, screen.state.mode
    assert_equal "jellybean", screen.current_item
    assert_equal [
      "Fruits",
      "> jellybean",
      "",
      "",
      "",
      "",
      "",
      "/jel  1/1",
    ], frame(screen)
  end

  def test_search_backspace_widens_the_filter
    screen = FruitScreen.new(items: FRUITS)
    press(screen, '/', 'e', 'r', "\u007F", "\b", 'n')

    assert_equal "n", screen.state.query
    assert_equal %w[banana jellybean lemon], screen.visible_items
  end

  def status(screen)
    screen.status_line
  end

  def test_completing_prompt_shows_choices_moves_accepts_and_submits
    screen = CompleteScreen.new(items: FRUITS)
    press(screen, 't', *"fix @hi".chars)

    assert_equal "todo: fix @hi_  @hi ▸ [hiiro] hiiro-config rehiiro", status(screen)

    press(screen, :down)

    assert_equal "todo: fix @hi_  @hi ▸ hiiro [hiiro-config] rehiiro", status(screen)

    press(screen, :tab)

    assert_equal "fix @hiiro-config ", screen.state.prompt_text
    assert_equal "todo: fix @hiiro-config _", status(screen)

    press(screen, '@', 'r', 'e', :enter)

    assert_equal :prompt, screen.state.mode
    assert_equal "fix @hiiro-config @rehiiro ", screen.state.prompt_text
    assert_equal [], screen.answers

    press(screen, :enter)

    assert_equal ["fix @hiiro-config @rehiiro "], screen.answers
    assert_equal :list, screen.state.mode
    assert_equal "1/6", status(screen)
  end

  def test_field_prompt_lists_every_choice_and_narrows
    screen = CompleteScreen.new(items: FRUITS)
    press(screen, 'f')

    assert_equal "table: _  ▸ [link] project sha sound t", status(screen)

    press(screen, 'p', 'r')

    assert_equal "table: pr_  pr ▸ [project]", status(screen)

    press(screen, :enter)

    assert_equal "table: project_", status(screen)

    press(screen, :enter)

    assert_equal ["project"], screen.answers
  end

  def test_prompt_edits_mid_text_with_left_home_end_and_ctrl_u
    screen = PromptScreen.new(items: FRUITS)
    press(screen, 'n', 'a', 'b', 'c', :left, :left, 'x')

    assert_equal "axbc", screen.state.prompt_text
    assert_equal "name: ax_bc", status(screen)

    press(screen, :home, 'y')

    assert_equal "name: y_axbc", status(screen)

    press(screen, :delete, :end, 'z')

    assert_equal "name: yxbcz_", status(screen)

    press(screen, :ctrl_u)

    assert_equal "", screen.state.prompt_text
    assert_equal "name: _", status(screen)
  end

  def test_read_key_maps_tab_ctrl_u_and_escape_sequences
    reader = KeyReader.new
    keys = ["\t", "\u0015", "\e[H", "\e[F", "\e[1~", "\e[4~", "\e[3~", "\e[A", "\e[2~", "\e[3", "\e[Z", "\e"]

    assert_equal [:tab, :ctrl_u, :home, :end, :home, :end, :delete, :up, :escape, :escape, :escape, :escape],
      keys.map { |text| reader.read_key(FakeInput.new(text)) }
  end

  def test_subclass_key_binding_dispatches_to_its_method
    screen = CustomKeyScreen.new(items: FRUITS)
    press(screen, 'j', 'x')

    assert_equal "custom on banana  2/6", frame(screen).last
    assert_equal :custom, CustomKeyScreen.key_map['x']
    assert_nil Hiiro::Tui::Screen.key_map['x']
    assert_nil FruitScreen.key_map['x']
  end

  def test_unknown_keys_are_ignored_and_quit_keys_stop
    screen = FruitScreen.new(items: FRUITS)

    assert_equal [:continue, :continue], press(screen, 'z', :enter)
    assert_equal "> apple", frame(screen)[1]
    assert_equal [false, false, false], [
      FruitScreen.new(items: FRUITS).handle_key('q'),
      FruitScreen.new(items: FRUITS).handle_key(:escape),
      FruitScreen.new(items: FRUITS).handle_key(:ctrl_c),
    ]
  end

  def test_detail_pane_appears_when_detail_lines_returns_lines
    screen = DetailScreen.new(items: FRUITS)
    press(screen, 'j')

    assert_equal [
      "Fruits",
      "  apple            │name: banana",
      "> banana           │length: 6",
      "  cherry           │",
      "  jellybean        │",
      "  kiwi             │",
      "  lemon            │",
      "2/6",
    ], frame(screen)
  end

  def test_list_screen_keeps_its_footer_and_quit_behaviour
    screen = Hiiro::Tui::ListScreen.new(items: %w[one two three])

    assert_equal [
      "> one",
      "  two",
      "  three",
      "",
      "",
      "",
      "",
      "Showing 1-3 of 3",
    ], frame(screen)

    assert_equal :continue, screen.handle_key('j')
    assert_equal 1, screen.cursor
    assert_equal 0, screen.top
    assert_equal 0, screen.horizontal_offset
    assert_equal %w[one two three], screen.visible_items
    assert_equal "  one", frame(screen)[0]
    assert_equal "> two", frame(screen)[1]
    assert_equal false, screen.handle_key('q')
  end

  def test_prompt_shows_label_and_buffer_in_the_status_line
    screen = PromptScreen.new(items: FRUITS)
    press(screen, 'n', 'a', 'b')

    assert_equal :prompt, screen.state.mode
    assert_equal [
      "Fruits",
      "> apple",
      "  banana",
      "  cherry",
      "  jellybean",
      "  kiwi",
      "  lemon",
      "name: ab_",
    ], frame(screen)
  end

  def test_prompt_enter_passes_text_to_block_and_returns_to_list
    screen = PromptScreen.new(items: FRUITS)
    press(screen, 'n', 'a', 'x', "\u007F", 'b', :enter)

    assert_equal ["ab"], screen.answers
    assert_equal :list, screen.state.mode
    assert_equal "1/6", frame(screen).last
  end

  def test_prompt_escape_does_not_call_block
    screen = PromptScreen.new(items: FRUITS)

    assert_equal [:continue] * 3, press(screen, 'n', 'a', :escape)
    assert_equal [], screen.answers
    assert_equal :list, screen.state.mode
    assert_equal "1/6", frame(screen).last
  end

  def test_prompt_ctrl_c_quits
    screen = PromptScreen.new(items: FRUITS)

    assert_equal [:continue, :continue, false], press(screen, 'n', 'a', :ctrl_c)
    assert_equal [], screen.answers
  end

  def test_prompt_block_can_chain_another_prompt
    screen = PromptScreen.new(items: FRUITS)
    press(screen, 'c')

    assert_equal "first: x_", frame(screen).last

    press(screen, 'y', :enter)

    assert_equal :prompt, screen.state.mode
    assert_equal "second: _", frame(screen).last

    press(screen, 'z', :enter)

    assert_equal [["xy", "z"]], screen.answers
    assert_equal "1/6", frame(screen).last
  end

  def test_unbound_list_key_reaches_unhandled_key
    screen = PromptScreen.new(items: FRUITS)
    press(screen, 'z', 'j', :enter)

    assert_equal ['z', :enter], screen.unhandled
    assert_equal "> banana", frame(screen)[2]
  end
end
