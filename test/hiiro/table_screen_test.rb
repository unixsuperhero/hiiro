require "test_helper"

class TableScreenTest < Minitest::Test
  HINT = "[/]search [@]table [g]scope [a]dd [r]ename [e]dit [d]elete [T]ag [m]o…".freeze
  BLANK = " " * 34

  def setup
    clear_rows
    @task = Hiiro::TaskRecord.create(name: "alpha")
    Hiiro::Table.named("link").add("gh", value: "github.com")
    Hiiro::Table.named("link").add("hn", value: "news.com", task_id: @task.id)
    Hiiro::Table.named("sound").add("ping", value: "Ping.aiff", short: "p")
  end

  def teardown = clear_rows

  def clear_rows
    [Hiiro::RegistryEntry, Hiiro::Tag, Hiiro::TaskRecord].each { |model| model.dataset.delete }
  end

  def screen_for(scope: Hiiro::TableScope.global, actions: {})
    Hiiro::TableScreen.new(scope:, actions: Hiiro::TableActions.new(actions))
  end

  def press(screen, *keys)
    keys.each { |key| screen.handle_key(key) }
  end

  def type(screen, text)
    press(screen, *text.chars, :enter)
  end

  def frame(screen, rows: 10)
    screen.frame(rows:, cols: 70)
  end

  def entry(name) = Hiiro::RegistryEntry.first(name:)

  def test_initial_frame_lists_every_table_with_detail
    assert_equal [
      "tables  scope:global  table:*",
      HINT,
      ">   link     gh               git…│table  link",
      "    link     hn               new…│name   gh",
      "    sound    ping             Pin…│short",
      "#{BLANK}│desc",
      "#{BLANK}│value  github.com",
      "#{BLANK}│tags",
      "#{BLANK}│task   -",
      "1/3",
    ], frame(screen_for)
  end

  def test_g_toggles_to_task_scope_and_back
    screen = screen_for(scope: Hiiro::TableScope.global(@task))
    press(screen, 'j', 'g')

    assert_equal [
      "tables  scope:task(@alpha)  table:*",
      HINT,
      ">   link     hn               new…│table  link",
      "#{BLANK}│name   hn",
      "#{BLANK}│short",
      "#{BLANK}│desc",
      "#{BLANK}│value  news.com",
      "#{BLANK}│tags",
      "#{BLANK}│task   alpha",
      "scope: task(@alpha)  1/1",
    ], frame(screen)

    press(screen, 'g')

    assert_equal "tables  scope:global  table:*", frame(screen)[0]
    assert_equal "scope: global  1/3", frame(screen).last
  end

  def test_at_completes_a_table_name_and_switches_to_it
    screen = screen_for
    press(screen, '@', 's', 'o')

    assert_equal "table: so_  so ▸ [sound]", frame(screen).last

    press(screen, :enter)

    assert_equal :prompt, screen.state.mode
    assert_equal "table: sound_", frame(screen).last

    press(screen, :enter)

    assert_equal [
      "tables  scope:global  table:sound",
      HINT,
      ">   sound    ping             Pin…│table  sound",
      "#{BLANK}│name   ping",
      "#{BLANK}│short  p",
      "#{BLANK}│desc",
      "#{BLANK}│value  Ping.aiff",
      "#{BLANK}│tags",
      "#{BLANK}│task   -",
      "1/1",
    ], frame(screen)
  end

  def test_search_matches_tags_and_short_names
    entry("hn").tag("daily")
    screen = screen_for
    press(screen, '/', *"dai".chars)

    assert_equal [">   link     hn               new…│table  link"], frame(screen)[2, 1]
    assert_equal "/dai_", frame(screen).last

    press(screen, *(["\u007F"] * 3), 'p', :enter)

    assert_equal %w[ping], screen.visible_items.map(&:name)
  end

  def test_add_prompts_for_name_value_and_table
    screen = screen_for(scope: Hiiro::TableScope.task(@task))
    press(screen, 'a', 'n', '1')

    assert_equal "name: n1_", frame(screen).last

    press(screen, :enter)
    type(screen, "v1")

    assert_equal "table: link_", frame(screen).last

    press(screen, :enter)

    assert_equal ["link", "v1", @task.id], [entry("n1").resource_type, entry("n1").value, entry("n1").task_id]
    assert_equal [
      "tables  scope:task(@alpha)  table:*",
      HINT,
      ">   link     hn               new…│table  link",
      "    link     n1               v1  │name   hn",
      "#{BLANK}│short",
      "#{BLANK}│desc",
      "#{BLANK}│value  news.com",
      "#{BLANK}│tags",
      "#{BLANK}│task   alpha",
      "added link/n1  1/2",
    ], frame(screen)
  end

  def test_add_with_existing_name_reports_it
    screen = screen_for
    press(screen, 'a')
    type(screen, "gh")
    type(screen, "dup")
    press(screen, :enter)

    assert_equal "exists: link/gh  1/3", frame(screen).last
    assert_equal "github.com", entry("gh").value
  end

  def test_r_renames_the_current_entry
    screen = screen_for
    press(screen, 'j', 'r')

    assert_equal "rename hn to: _", frame(screen).last

    type(screen, "x")

    assert_nil entry("hn")
    assert_equal [
      "tables  scope:global  table:*",
      HINT,
      "    link     gh               git…│table  link",
      ">   link     x                new…│name   x",
      "    sound    ping             Pin…│short",
      "#{BLANK}│desc",
      "#{BLANK}│value  news.com",
      "#{BLANK}│tags",
      "#{BLANK}│task   alpha",
      "2/3",
    ], frame(screen)
  end

  def test_capital_r_renames_the_table_and_follows_the_filter
    screen = Hiiro::TableScreen.new(scope: Hiiro::TableScope.global, table: "link", actions: Hiiro::TableActions.new({}))
    press(screen, 'R')

    assert_equal "rename table link to: _", frame(screen).last

    type(screen, "web")

    assert_equal %w[web web sound], %w[gh hn ping].map { |name| entry(name).resource_type }
    assert_equal "tables  scope:global  table:web", frame(screen)[0]
    assert_equal ">   web      gh               git…│table  web", frame(screen)[2]
    assert_equal "renamed link to web  1/2", frame(screen).last
  end

  def test_e_edits_the_value_starting_from_the_current_one
    screen = screen_for
    press(screen, 'e')

    assert_equal "value: github.com_", frame(screen).last

    press(screen, *(["\u007F"] * 10))
    type(screen, "gl")

    assert_equal "gl", entry("gh").value
    assert_equal "#{BLANK}│value  gl", frame(screen)[6]
  end

  def test_space_marks_rows_and_d_deletes_them_with_their_tags
    entry("gh").tag("old")
    screen = screen_for
    press(screen, ' ', ' ')

    assert_equal [
      "  * link     gh               git…│table  sound",
      "  * link     hn               new…│name   ping",
      ">   sound    ping             Pin…│short  p",
    ], frame(screen)[2, 3]

    press(screen, 'd')

    assert_equal "delete 2 entries? (y/n): _", frame(screen).last

    type(screen, "y")

    assert_equal %w[ping], Hiiro::RegistryEntry.select_map(:name)
    assert_equal 0, Hiiro::Tag.where(taggable_type: "RegistryEntry").count
    assert_empty screen.marked
    assert_equal [
      "tables  scope:global  table:*",
      HINT,
      ">   sound    ping             Pin…│table  sound",
      "#{BLANK}│name   ping",
      "#{BLANK}│short  p",
      "#{BLANK}│desc",
      "#{BLANK}│value  Ping.aiff",
      "#{BLANK}│tags",
      "#{BLANK}│task   -",
      "deleted 2  1/1",
    ], frame(screen)
  end

  def test_d_answered_with_anything_but_y_keeps_rows
    screen = screen_for
    press(screen, 'd')
    type(screen, "n")

    assert_equal 3, Hiiro::RegistryEntry.count
    assert_equal "1/3", frame(screen).last
  end

  def test_capital_t_tags_and_untags_the_current_row
    entry("gh").tag("old")
    screen = screen_for
    press(screen, 'T')

    assert_equal "tags: _  ▸ [old]", frame(screen).last

    type(screen, "x -old")

    assert_equal %w[x], entry("gh").tags
    assert_equal "#{BLANK}│tags   x", frame(screen)[7]
    assert_equal "tagged 1  1/3", frame(screen).last
  end

  def test_m_moves_marked_rows_to_another_table
    screen = screen_for
    press(screen, ' ', 'm')

    assert_equal "move to table: _  ▸ [link] sound", frame(screen).last

    type(screen, "sfx")

    assert_equal "sfx", entry("gh").resource_type
    assert_equal [
      "tables  scope:global  table:*",
      HINT,
      ">   link     hn               new…│table  link",
      "  * sfx      gh               git…│name   hn",
      "    sound    ping             Pin…│short",
      "#{BLANK}│desc",
      "#{BLANK}│value  news.com",
      "#{BLANK}│tags",
      "#{BLANK}│task   alpha",
      "moved 1 to sfx  1/3",
    ], frame(screen)
  end

  def test_action_letters_come_from_table_actions_and_run
    screen = screen_for(actions: { 'link' => { 'o' => 'echo {value}' } })

    assert_equal [
      "#{BLANK}│",
      "#{BLANK}│actions:",
      "#{BLANK}│  o  echo {value}",
      "#{BLANK}│  y  pbcopy <<< {value}",
    ], frame(screen, rows: 14)[9, 4]

    out, = capture_subprocess_io { press(screen, 'o') }

    assert_equal "github.com\n", out
    assert_equal "ran: echo github.com  1/3", frame(screen).last
  end

  def test_unknown_letter_without_an_action_is_ignored
    screen = screen_for
    press(screen, 'z')

    assert_equal "1/3", frame(screen).last
  end

  def test_toggle_scope_without_a_task_says_so
    screen = Hiiro::TableScreen.new(scope: Hiiro::TableScope.global, actions: Hiiro::TableActions.new({}))
    original = Hiiro::TableScope.method(:resolve)
    Hiiro::TableScope.define_singleton_method(:resolve) { |**| nil }
    screen.handle_key('g')
    assert_equal 'no current task to scope to', screen.state.message
    assert screen.scope.global?
  ensure
    Hiiro::TableScope.define_singleton_method(:resolve, original)
  end

end
