require "test_helper"
require_relative "tuios_fake_runner"

class TuiosScreenTest < Minitest::Test
  include TuiosFixtures

  HEADER = "tuios  host:local  scope:global  4 windows in 3 sessions  attention: 1 ask, 2 finished".freeze
  HINT = "[enter]jump [/]search [c]apture [R]eload [H]osts [g]scope [n]ame [M]in [N]ew [m]ail [y]ank id [q]uit".freeze
  BLANK = " " * 54
  A2 = "  *alpha  ws1  ● inbox remote host capture  (min)  omp│".freeze
  A3 = "  *alpha  ws2  ? ◑ Md file open with mdo…  claude-code│".freeze
  A1 = "  *alpha  ws2  ✓ π > Implement JSON Task Status …  omp│".freeze
  Z1 = "   zeta   ws1  ● π ⠹ STAR: Configure Unique Star…  omp│".freeze
  A2_PANE = [
    "title    inbox remote host capture", "session  alpha", "ws       1", "state    working", "harness  omp",
    "message  -", "cwd      /Users/me/proj/hiiro", "cmd      -", "id       id-a2", "",
  ].freeze
  OWN = { "TUIOS_SESSION" => "alpha", "TUIOS_PANE_ID" => "id-a2" }.freeze
  BACKSPACE = "\u007F".freeze

  def setup
    Hiiro::TaskRecord.dataset.delete
    @runner = TuiosFakeRunner.new(answers)
    @copied = []
  end

  def teardown
    Hiiro::TaskRecord.dataset.delete
  end

  def screen_for(runner: @runner, own: OWN, **kw)
    listing = Hiiro::TuiosListing.load(runner:)
    runner.calls.clear
    Hiiro::TuiosScreen.new(listing:, own:, clipboard: ->(text) { @copied << text }, **kw)
  end

  def press(screen, *keys) = keys.each { |key| screen.handle_key(key) }

  def type(screen, text) = press(screen, *text.chars, :enter)

  def frame(screen, rows: 14) = screen.frame(rows:, cols: 110)

  # The detail pane is 55 columns wide.
  def right(text) = text.length > 55 ? "#{text[0, 54]}…" : text

  def test_initial_list_shows_one_row_per_window_with_the_own_session_marked
    assert_equal [
      HEADER,
      HINT,
      "> *alpha  ws1  ● inbox remote host capture  (min)  omp│title    inbox remote host capture",
      "#{A3}session  alpha",
      "#{A1}ws       1",
      "#{Z1}state    working",
      "#{BLANK}│harness  omp",
      "#{BLANK}│message  -",
      "#{BLANK}│cwd      /Users/me/proj/hiiro",
      "#{BLANK}│cmd      -",
      "#{BLANK}│id       id-a2",
      "#{BLANK}│",
      "#{BLANK}│screen   (press c)",
      "1/4",
    ], frame(screen_for)
  end

  def test_search_matches_the_title
    screen = screen_for
    type(screen, "/mdoc")

    assert_equal [
      HEADER,
      HINT,
      "> *alpha  ws2  ? ◑ Md file open with mdo…  claude-code│title    ◑ Md file open with mdoc cli tool",
      "#{BLANK}│session  alpha",
      "#{BLANK}│ws       2",
      "#{BLANK}│state    needs_input",
      "#{BLANK}│harness  claude-code",
      "#{BLANK}│message  Open the file?",
      "#{BLANK}│cwd      -",
      "#{BLANK}│cmd      claude",
      "#{BLANK}│id       id-a3",
      "#{BLANK}│",
      "#{BLANK}│screen   (press c)",
      "/mdoc  1/1",
    ], frame(screen)
  end

  def test_c_captures_the_pane_into_the_detail_and_r_clears_it
    @runner.answers[%w[capture-pane]] = "line one\nline two\nline three\n\n\n"
    screen = screen_for
    press(screen, "c")

    assert_equal [["capture-pane", "-s", "alpha", "-w", "id-a2", "--lines", "20"]], @runner.calls
    assert_equal [
      HEADER,
      HINT,
      "> *alpha  ws1  ● inbox remote host capture  (min)  omp│title    inbox remote host capture",
      "#{A3}session  alpha",
      "#{A1}ws       1",
      "#{Z1}state    working",
      "#{BLANK}│harness  omp",
      "#{BLANK}│message  -",
      "#{BLANK}│cwd      /Users/me/proj/hiiro",
      "#{BLANK}│cmd      -",
      "#{BLANK}│id       id-a2",
      "#{BLANK}│",
      "#{BLANK}│screen (3)",
      "#{BLANK}│line one",
      "#{BLANK}│line two",
      "#{BLANK}│line three",
      "#{BLANK}│",
      "captured 3 lines  1/4",
    ], frame(screen, rows: 18)

    press(screen, "R")

    assert_equal %w[ls --json], @runner.calls[1]
    assert_equal [
      HEADER,
      HINT,
      "> *alpha  ws1  ● inbox remote host capture  (min)  omp│title    inbox remote host capture",
      "#{A3}session  alpha",
      "#{A1}ws       1",
      "#{Z1}state    working",
      "#{BLANK}│harness  omp",
      "#{BLANK}│message  -",
      "#{BLANK}│cwd      /Users/me/proj/hiiro",
      "#{BLANK}│cmd      -",
      "#{BLANK}│id       id-a2",
      "#{BLANK}│",
      "#{BLANK}│screen   (press c)",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "reloaded  1/4",
    ], frame(screen, rows: 18)
  end

  def test_c_reads_glyphs_from_a_window_without_a_locale
    @runner.answers[%w[capture-pane]] = "π > done ✓\n".dup.force_encoding(Encoding::US_ASCII)
    screen = screen_for
    press(screen, "c")

    assert_equal ["π > done ✓"], screen.captures["id-a2"]
    assert_equal "captured 1 lines  1/4", frame(screen).last
  end

  def test_capture_errors_become_the_status_message
    @runner.answers[%w[capture-pane]] = Hiiro::Error.new("tuios capture-pane failed: no such window")
    screen = screen_for
    press(screen, "c")

    assert_equal "tuios capture-pane failed: no such window  1/4", frame(screen).last
  end

  def test_h_adds_one_row_per_remote_session_and_enter_on_it_shows_the_attach_command
    screen = screen_for
    press(screen, "H")

    assert_includes @runner.calls, %w[ls --all-hosts --json]
    assert_equal [
      "tuios  host:all  scope:global  4 windows in 5 sessions  attention: 1 ask, 2 finished",
      HINT,
      "> *alpha        ws1  ● inbox remote host …  (min)  omp│title    inbox remote host capture",
      "  *alpha        ws2  ? ◑ Md file open wi…  claude-code│session  alpha",
      "  *alpha        ws2  ✓ π > Implement JSON Task S…  omp│ws       1",
      "   zeta         ws1  ● π ⠹ STAR: Configure Uniqu…  omp│state    working",
      "   m3pro:fleet  -      (1 windows)                    │harness  omp",
      "   m3pro:m3pro  -    ✓ (3 windows)                    │message  -",
      "#{BLANK}│cwd      /Users/me/proj/hiiro",
      "#{BLANK}│cmd      -",
      "#{BLANK}│id       id-a2",
      "#{BLANK}│",
      "#{BLANK}│screen   (press c)",
      "1/6",
    ], frame(screen)

    press(screen, "j", "j", "j", "j", "j")
    @runner.calls.clear

    assert_equal :continue, screen.handle_key(:enter)
    assert_equal [], @runner.calls
    assert_equal [
      "   m3pro:fleet  -      (1 windows)                    │",
      ">  m3pro:m3pro  -    ✓ (3 windows)                    │attach   tuios attach --host m3pro m3pro",
      "#{BLANK}│",
    ], frame(screen)[6, 3]
    assert_equal "remote session: tuios attach --host m3pro m3pro  6/6", frame(screen).last
    assert_equal ["host     m3pro", "session  m3pro", "windows  3", "state    done", "", "attach   tuios attach --host m3pro m3pro"],
                 screen.detail_lines(screen.current_item)

    press(screen, "H")

    assert_equal HEADER, frame(screen)[0]
    assert_equal 4, screen.items.length
  end

  def test_g_scopes_to_the_windows_under_the_current_task_directory
    Dir.mktmpdir("tuiostask") do |tmp|
      dir = File.realpath(tmp)
      task = Hiiro::TaskRecord.create_task("tcli")
      task.update(primary_directory: dir)
      screen = screen_for(runner: TuiosFakeRunner.new(answers(cwd: dir)), current: task)
      press(screen, "j", "j", "j", "g")

      assert_equal [
        "tuios  host:local  scope:task(@tcli)  2 windows in 3 sessions  attention: 1 ask, 2 finished",
        HINT,
        "  *alpha  ws1  ● inbox remote host capture  (min)  omp│title    π > Implement JSON Task Status Management",
        "> *alpha  ws2  ✓ π > Implement JSON Task Status …  omp│session  alpha",
        "#{BLANK}│ws       2",
        "#{BLANK}│state    done",
        "#{BLANK}│harness  omp",
        "#{BLANK}│message  -",
        "#{BLANK}│#{right("cwd      #{dir}")}",
        "#{BLANK}│cmd      bun",
        "#{BLANK}│id       id-a1",
        "#{BLANK}│",
        "#{BLANK}│screen   (press c)",
        "2/2",
      ], frame(screen)

      press(screen, "g")

      assert_equal HEADER, frame(screen)[0]
      assert_equal "3/4", frame(screen).last
    end
  end

  def test_g_without_a_matching_task_reports_it
    screen = screen_for
    press(screen, "g")

    assert_equal "no current task to scope to  1/4", frame(screen).last

    task = Hiiro::TaskRecord.create_task("elsewhere")
    task.update(primary_directory: "/nowhere")

    assert_equal :global, screen_for(current: task, scope: :task).scope
  end

  def test_n_prompts_with_the_title_and_renames_the_window
    @runner.answers[%w[set-window]] = ""
    screen = screen_for
    press(screen, "n")

    assert_equal "name: inbox remote host capture_", frame(screen).last

    press(screen, *Array.new(25, BACKSPACE))
    type(screen, "x")

    assert_equal ["set-window", "-s", "alpha", "-w", "id-a2", "--name", "x"], @runner.calls.first
    assert_equal %w[ls --json], @runner.calls[1]
    assert_equal "1/4", frame(screen).last
  end

  def test_m_restores_a_minimized_window_and_minimizes_a_shown_one
    @runner.answers[%w[set-window]] = ""
    screen = screen_for
    press(screen, "M")

    assert_equal ["set-window", "-s", "alpha", "-w", "id-a2", "--restore"], @runner.calls.first

    press(screen, "j", "j", "M")

    assert_equal ["set-window", "-s", "alpha", "-w", "id-a1", "--minimize"], @runner.calls_for("set-window").last
    assert_equal "3/4", frame(screen).last
  end

  def test_n_opens_a_window_in_the_row_session_and_directory_and_selects_it
    sessions = ls_sessions
    sessions[1]["windows"] << { "id" => "id-new", "title" => "child", "agent_state" => "none", "workspace" => 3 }
    @runner.answers[%w[new-window]] = "id-new\n"
    screen = screen_for
    press(screen, "N")

    assert_equal "new window: _", frame(screen).last

    @runner.answers[%w[ls --json]] = JSON.generate(sessions)
    type(screen, "child")

    assert_equal ["new-window", "child", "-s", "alpha", "--cwd", HIIRO, "--print-id", "--no-focus"], @runner.calls.first
    assert_equal [
      "tuios  host:local  scope:global  5 windows in 3 sessions  attention: 1 ask, 2 finished",
      HINT,
      "#{A2}title    child",
      "#{A3}session  alpha",
      "#{A1}ws       3",
      "> *alpha  ws3    child                                │state    none",
      "#{Z1}harness  -",
    ], frame(screen)[0, 7]
    assert_equal "opened id-new  4/5", frame(screen).last
  end

  def test_n_omits_cwd_when_the_window_has_none
    @runner.answers[%w[new-window]] = "id-new\n"
    screen = screen_for
    press(screen, "j", "N")
    type(screen, "child")

    assert_equal ["new-window", "child", "-s", "alpha", "--print-id", "--no-focus"], @runner.calls.first
  end

  def test_m_sends_mail_from_the_own_pane
    @runner.answers[%w[send-agent-message]] = ""
    screen = screen_for
    press(screen, "j", "j", "m")

    assert_equal "message: _", frame(screen).last

    type(screen, "hello from ui")

    assert_equal [["send-agent-message", "hello from ui", "-s", "alpha", "-w", "id-a1", "--from", "id-a2"]], @runner.calls
    assert_equal "sent  3/4", frame(screen).last
  end

  def test_m_refuses_without_an_own_pane_and_marks_no_session
    screen = screen_for(own: {})
    press(screen, "j", "j", "m")

    assert_equal [], @runner.calls
    assert_equal "   alpha  ws1  ● inbox remote host capture  (min)  omp│title    π > Implement JSON Task Status Management", frame(screen)[2]
    assert_equal "no own pane  3/4", frame(screen).last
  end

  def test_y_copies_the_window_id
    screen = screen_for
    press(screen, "j", "y")

    assert_equal ["id-a3"], @copied
    assert_equal "copied id-a3  2/4", frame(screen).last
  end

  def test_enter_jumps_to_the_window_and_finishes_the_screen
    @runner.answers[%w[jump-window]] = ""
    screen = screen_for
    press(screen, "j")

    assert_equal true, screen.handle_key(:enter)
    assert_equal [["jump-window", "id-a3"]], @runner.calls
  end

  def test_jump_errors_keep_the_screen_open
    @runner.answers[%w[jump-window]] = Hiiro::Error.new("tuios jump-window failed: no client")
    screen = screen_for

    assert_equal :continue, screen.handle_key("o")
    assert_equal "tuios jump-window failed: no client  1/4", frame(screen).last
  end

  def test_an_empty_listing_reports_no_window_on_every_action
    runner = TuiosFakeRunner.new(%w[ls --json] => "[]", %w[list-attention --json] => "{}")
    screen = screen_for(runner:)
    press(screen, "c")

    assert_equal "tuios  host:local  scope:global  0 windows in 0 sessions  attention: none", frame(screen)[0]
    assert_equal "No windows.", frame(screen)[2]
    assert_equal "no window  0/0", frame(screen).last
    assert_equal [], runner.calls

    press(screen, "n", "M", "N", "m", "y")

    assert_equal [], runner.calls
    assert_equal [], @copied
    assert_equal :continue, screen.handle_key(:enter)
    assert_equal false, screen.run
  end
end
