require "test_helper"
require "hiiro/tui"

class TuiTest < Minitest::Test
  FRUITS = %w[apple banana cherry jellybean kiwi lemon].freeze

  class FruitScreen < Hiiro::Tui::Screen
    def header_lines
      ['Fruits']
    end
  end

  class PickScreen < FruitScreen
    attr_reader :picks

    def initialize(**kwargs)
      super
      @picks = []
    end

    def pick_candidates
      %w[sonnet opus haiku solo]
    end

    def picked(candidate)
      @picks << candidate
    end
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

  def test_pick_filters_candidates_by_prefix_and_enter_picks_first
    screen = PickScreen.new(items: FRUITS)
    press(screen, '@', 's', 'o')

    assert_equal :pick, screen.state.mode
    assert_equal [
      "Fruits",
      "> apple",
      "  banana",
      "  cherry",
      "  jellybean",
      "  kiwi",
      "  lemon",
      "@so_  [sonnet] [solo]",
    ], frame(screen)

    press(screen, 'l', :enter)

    assert_equal ["solo"], screen.picks
    assert_equal :list, screen.state.mode
    assert_equal "", screen.state.pick_query
    assert_equal "1/6", frame(screen).last
  end

  def test_escape_in_pick_mode_cancels_without_picking
    screen = PickScreen.new(items: FRUITS)
    press(screen, '@', 'o')

    assert_equal "@o_  [opus]", frame(screen).last

    assert_equal [:continue], press(screen, :escape)
    assert_equal [], screen.picks
    assert_equal :list, screen.state.mode
    assert_equal "1/6", frame(screen).last
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
end
