require "test_helper"
require "hiiro/tui"

class LineEditorTest < Minitest::Test
  PROJECTS = %w[hiiro hiiro-config rehiiro thinktank].freeze
  RANKED = %w[hiiro hiiro-config rehiiro thinktank h2 old-home.2020 home-ic].freeze

  def editor(text = '', triggers: { '@' => -> { PROJECTS } })
    Hiiro::Tui::LineEditor.new(text:, triggers:)
  end

  def test_insert_lands_at_the_cursor_after_left
    ed = editor('ac')
    ed.left
    ed.insert('b')

    assert_equal ['abc', 2], [ed.text, ed.cursor]
  end

  def test_home_end_delete_and_kill_line
    ed = editor('abc')
    ed.home
    ed.delete

    assert_equal ['bc', 0], [ed.text, ed.cursor]

    ed.end_of_line
    ed.backspace

    assert_equal ['b', 1], [ed.text, ed.cursor]

    ed.kill_line

    assert_equal ['', 0], [ed.text, ed.cursor]
  end

  def test_token_needs_the_trigger_at_the_start_or_after_a_space
    assert_equal({ start: 0, trigger: '@', query: 'hi' }, editor('@hi').token)
    assert_equal({ start: 4, trigger: '@', query: 'hi' }, editor('fix @hi').token)
    assert_nil editor('fix@hi').token
    assert_nil editor('@hi there').token
    assert_nil editor('plain', triggers: {}).token
  end

  def test_field_trigger_takes_the_word_at_the_cursor
    assert_equal({ start: 0, trigger: '', query: '' }, editor('', triggers: { '' => -> { [] } }).token)
    assert_equal({ start: 2, trigger: '', query: 'b' }, editor('a b', triggers: { '' => -> { [] } }).token)
  end

  def test_choices_rank_the_source_for_the_query
    assert_equal %w[hiiro hiiro-config rehiiro], editor('@hii').choices
    assert_equal [], editor('fix').choices
  end

  def test_source_is_called_once_per_editor
    calls = 0
    ed = editor('@h', triggers: { '@' => -> { calls += 1; PROJECTS } })
    ed.choices
    ed.insert('i')
    ed.choices

    assert_equal 1, calls
  end

  def test_accept_on_a_trigger_token_adds_one_space
    ed = editor('fix @hii')

    assert_equal true, ed.accept
    assert_equal ['fix @hiiro ', 11], [ed.text, ed.cursor]
    assert_equal [], ed.choices
    assert_equal false, ed.accept
  end

  def test_accept_on_a_field_adds_no_space_and_shows_nothing_more
    ed = editor('li', triggers: { '' => -> { %w[link project] } })
    ed.accept

    assert_equal ['link', 4], [ed.text, ed.cursor]
    assert_equal [], ed.choices
  end

  def test_select_moves_and_wraps_and_edits_reset_it
    ed = editor('@hii')
    ed.select(1)

    assert_equal 1, ed.selected

    ed.select(-2)

    assert_equal 2, ed.selected

    ed.select(-1)
    ed.accept

    assert_equal '@hiiro-config ', ed.text
    assert_equal 0, ed.selected
  end

  def test_fuzzy_rank_orders_by_score_length_then_name
    rank = ->(query) { Hiiro::Tui::Fuzzy.rank(RANKED, query) }

    assert_equal %w[hiiro hiiro-config rehiiro thinktank home-ic], rank.('hi')
    assert_equal %w[hiiro-config], rank.('cfg')
    assert_equal %w[hiiro hiiro-config rehiiro], rank.('hro')
    assert_equal %w[h2 old-home.2020], rank.('H2')
    assert_equal RANKED, rank.('')
  end

  def test_fuzzy_score_tiers
    score = ->(candidate, query) { Hiiro::Tui::Fuzzy.score(candidate, query) }

    assert_equal [0, 1, 2, 4, nil], [
      score.('hiiro', 'hi'),
      score.('rehiiro', 'hi'),
      score.('home-ic', 'hi'),
      score.('rehiiro', 'hro'),
      score.('h2', 'hi'),
    ]
  end
end
