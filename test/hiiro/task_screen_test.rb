require "test_helper"

class TaskScreenTest < Minitest::Test
  HEADER = "tasks  scope:global  closed:hidden".freeze
  HINT = "[enter]open [h]close [/]search [g]scope [A]closed [x]done [t]odo [n]ext [w]ait …".freeze
  BLANK = " " * 39

  class FakeOps
    attr_reader :calls

    def initialize = @calls = []

    def create(name)
      @calls << [:create, name]
      Hiiro::TaskRecord.create_task(name)
    end

    def save_current(task) = @calls << [:save_current, task.name]

    def open_workspace(task) = @calls << [:open_workspace, task.name]
  end

  def setup
    @home = ENV["HOME"]
    ENV["HOME"] = "/h"
    clear_rows
    @alpha = task("alpha", next_action: "ship")
    @beta = task("beta")
    task("beta/sub")
    task("gamma", status: "done")
    todo("alpha", "test one")
    todo("alpha", "test two", "done")
    todo("beta", "fix build")
    @ops = FakeOps.new
  end

  def teardown
    clear_rows
    ENV["HOME"] = @home
  end

  def clear_rows
    [Hiiro::TodoItem, Hiiro::TaskResource, Hiiro::TaskRecord, Hiiro::RegistryEntry].each { |model| model.dataset.delete }
  end

  def task(name, **fields) = Hiiro::TaskRecord.create(name:, status: "active", session: name, **fields)

  def todo(task_name, text, status = "not_started")
    Hiiro::TodoItem.create(text:, task_name:, status:, created_at: "2026-10-12")
  end

  def record(name) = Hiiro::TaskRecord.find_by_name(name)

  def screen_for(**kw) = Hiiro::TaskScreen.new(ops: @ops, **kw)

  def press(screen, *keys) = keys.each { |key| screen.handle_key(key) }

  def type(screen, text) = press(screen, *text.chars, :enter)

  def frame(screen) = screen.frame(rows: 14, cols: 80)

  ALPHA_COLLAPSED = "  ▸ alpha  active  (1)  next: ship     │".freeze

  def test_initial_tree_is_collapsed_with_counts_next_action_and_closed_tasks_hidden
    assert_equal [
      HEADER,
      HINT,
      "> ▸ alpha  active  (1)  next: ship     │name     alpha",
      "  ▸ beta  active  (1)                  │status   active",
      "#{BLANK}│next     ship",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  alpha",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/alpha",
      "#{BLANK}│todos (2)",
      "#{BLANK}│  [ ] test one",
      "#{BLANK}│  [x] test two",
      "1/2",
    ], frame(screen_for)
  end

  def test_enter_expands_todos_then_subtasks_and_h_collapses
    screen = screen_for
    press(screen, "j", :enter)

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA_COLLAPSED}name     beta",
      "> ▾ beta  active  (1)                  │status   active",
      "    [ ] fix build                      │next     -",
      "    ▸ beta/sub  active                 │waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (1)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│resources (0)",
      "2/4",
    ], frame(screen)

    press(screen, "h")

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA_COLLAPSED}name     beta",
      "> ▸ beta  active  (1)                  │status   active",
      "#{BLANK}│next     -",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (1)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│resources (0)",
      "2/2",
    ], frame(screen)
  end

  def test_h_on_a_todo_moves_to_its_task
    screen = screen_for
    press(screen, "j", "l", "j")

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA_COLLAPSED}task     beta",
      "  ▾ beta  active  (1)                  │id       3",
      ">   [ ] fix build                      │status   not_started",
      "    ▸ beta/sub  active                 │text     fix build",
      "#{BLANK}│tags     -",
      "#{BLANK}│created  2026-10-12",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "3/4",
    ], frame(screen)

    press(screen, "h")

    assert_equal "> ▾ beta  active  (1)                  │status   active", frame(screen)[3]
    assert_equal "2/4", frame(screen).last
  end

  def test_h_on_a_collapsed_subtask_moves_to_its_parent
    screen = screen_for
    press(screen, "j", :enter, "j", "j", "h")

    assert_equal "> ▾ beta  active  (1)                  │status   active", frame(screen)[3]
  end

  # Search keeps matching rows plus the tasks above them, all expanded; rows
  # that do not match (and tasks with no match beneath them) are hidden.
  def test_search_shows_matching_todos_under_their_expanded_task_and_hides_the_rest
    screen = screen_for
    type(screen, "/test")

    assert_equal [
      HEADER,
      HINT,
      "> ▾ alpha  active  (1)  next: ship     │name     alpha",
      "    [ ] test one                       │status   active",
      "    [x] test two                       │next     ship",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  alpha",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/alpha",
      "#{BLANK}│todos (2)",
      "#{BLANK}│  [ ] test one",
      "#{BLANK}│  [x] test two",
      "/test  1/3",
    ], frame(screen)

    screen = screen_for
    type(screen, "/one")

    assert_equal [
      "> ▾ alpha  active  (1)  next: ship     │name     alpha",
      "    [ ] test one                       │status   active",
      "#{BLANK}│next     ship",
    ], frame(screen)[2, 3]
    assert_equal "/one  1/2", frame(screen).last
    assert_equal Set.new, screen.expanded
  end

  def test_g_toggles_to_the_current_task_subtree
    screen = screen_for(current: @beta)
    press(screen, "g")

    assert_equal [
      "tasks  scope:task(@beta)  closed:hidden",
      HINT,
      "> ▾ beta  active  (1)                  │name     beta",
      "    [ ] fix build                      │status   active",
      "    ▸ beta/sub  active                 │next     -",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (1)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│resources (0)",
      "1/3",
    ], frame(screen)

    press(screen, "g")

    assert_equal HEADER, frame(screen)[0]
    assert_equal "2/4", frame(screen).last
  end

  def test_g_without_a_current_task_stays_global
    screen = screen_for
    press(screen, "g")

    assert_equal :global, screen.scope
    assert_equal "no current task  1/2", frame(screen).last
  end

  def test_capital_a_reveals_closed_tasks
    screen = screen_for
    press(screen, "A")

    assert_equal [
      "tasks  scope:global  closed:shown",
      HINT,
      "> ▸ alpha  active  (1)  next: ship     │name     alpha",
      "  ▸ beta  active  (1)                  │status   active",
      "  ▸ gamma  done                        │next     ship",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  alpha",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/alpha",
      "#{BLANK}│todos (2)",
      "#{BLANK}│  [ ] test one",
      "#{BLANK}│  [x] test two",
      "1/3",
    ], frame(screen)
  end

  def test_x_flips_a_todo_between_done_and_not_started
    screen = screen_for
    press(screen, :enter, "j", "x")

    assert_equal [
      HEADER,
      HINT,
      "  ▾ alpha  active  next: ship          │task     alpha",
      ">   [x] test one                       │id       1",
      "    [x] test two                       │status   done",
      "  ▸ beta  active  (1)                  │text     test one",
      "#{BLANK}│tags     -",
      "#{BLANK}│created  2026-10-12",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "#{BLANK}│",
      "2/4",
    ], frame(screen)
    assert_equal "done", Hiiro::TodoItem.first(text: "test one").status

    press(screen, "x")

    assert_equal [
      "  ▾ alpha  active  (1)  next: ship     │task     alpha",
      ">   [ ] test one                       │id       1",
      "    [x] test two                       │status   not_started",
    ], frame(screen)[2, 3]
    assert_equal "not_started", Hiiro::TodoItem.first(text: "test one").status
  end

  def test_t_adds_a_todo_to_the_task_under_the_cursor
    screen = screen_for
    press(screen, "j", "t")

    assert_equal "todo: _", frame(screen).last

    type(screen, "from ui")

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA_COLLAPSED}name     beta",
      "> ▾ beta  active  (2)                  │status   active",
      "    [ ] fix build                      │next     -",
      "    [ ] from ui                        │waiting  -",
      "    ▸ beta/sub  active                 │tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (2)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│  [ ] from ui",
      "added todo 4  2/5",
    ], frame(screen)
    assert_equal ["beta", nil, "not_started"], Hiiro::TodoItem.first(text: "from ui").values.values_at(:task_name, :subtask_name, :status)
  end

  def test_x_on_a_task_opens_the_todo_prompt
    screen = screen_for
    press(screen, "x")

    assert_equal "todo: _", frame(screen).last
  end

  def test_n_sets_and_clears_the_next_action
    screen = screen_for
    press(screen, "j", "n")
    type(screen, "deploy")

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA_COLLAPSED}name     beta",
      "> ▸ beta  active  (1)  next: deploy    │status   active",
      "#{BLANK}│next     deploy",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (1)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│resources (0)",
      "2/2",
    ], frame(screen)
    assert_equal "deploy", record("beta").next_action

    press(screen, "n")

    assert_equal "next action: deploy_", frame(screen).last

    press(screen, *(["\u007F"] * 6), :enter)

    assert_equal "> ▸ beta  active  (1)                  │status   active", frame(screen)[3]
    assert_nil record("beta").next_action
  end

  def test_w_sets_waiting_and_clearing_returns_the_task_to_active
    screen = screen_for
    press(screen, "w")
    type(screen, "review")

    assert_equal [
      HEADER,
      HINT,
      "> ▸ alpha  waiting  (1)  next: ship    │name     alpha",
      "  ▸ beta  active  (1)                  │status   waiting",
      "#{BLANK}│next     ship",
      "#{BLANK}│waiting  review",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  alpha",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/alpha",
      "#{BLANK}│todos (2)",
      "#{BLANK}│  [ ] test one",
      "#{BLANK}│  [x] test two",
      "1/2",
    ], frame(screen)
    assert_equal ["review", "waiting"], record("alpha").values.values_at(:waiting_on, :status)

    press(screen, "w", *(["\u007F"] * 6), :enter)

    assert_equal "> ▸ alpha  active  (1)  next: ship     │name     alpha", frame(screen)[2]
    assert_equal [nil, "active"], record("alpha").values.values_at(:waiting_on, :status)
  end

  def test_capital_d_after_y_marks_the_task_done
    screen = screen_for
    press(screen, "D")

    assert_equal "mark alpha done? (y/n): _", frame(screen).last

    type(screen, "y")

    assert_equal [
      HEADER,
      HINT,
      "> ▸ beta  active  (1)                  │name     beta",
      "#{BLANK}│status   active",
      "#{BLANK}│next     -",
      "#{BLANK}│waiting  -",
      "#{BLANK}│tree     -",
      "#{BLANK}│session  beta",
      "#{BLANK}│code dir -",
      "#{BLANK}│home     /h/notes/work/beta",
      "#{BLANK}│todos (1)",
      "#{BLANK}│  [ ] fix build",
      "#{BLANK}│resources (0)",
      "alpha done  1/1",
    ], frame(screen)
    alpha = record("alpha")
    assert_equal "done", alpha.status
    refute_nil alpha.completed_at
    assert_nil alpha.archived_at
  end

  def test_capital_d_with_anything_but_y_changes_nothing
    screen = screen_for
    press(screen, "D")
    type(screen, "n")

    assert_equal "active", record("alpha").status
  end

  def test_capital_n_creates_the_task_through_ops_and_selects_it
    screen = screen_for
    press(screen, "N")

    assert_equal "new task: _  ▸ [alpha] beta beta/sub gamma", frame(screen).last

    type(screen, "delta")

    assert_equal [[:create, "delta"]], @ops.calls
    assert_equal [
      "#{ALPHA_COLLAPSED}name     delta",
      "  ▸ beta  active  (1)                  │status   active",
      "> ▸ delta  active                      │next     -",
    ], frame(screen)[2, 3]
    assert_equal "created delta  3/3", frame(screen).last
  end

  def test_ops_errors_become_the_status_message
    ops = Object.new
    def ops.create(_name) = raise(Hiiro::Error, "bad name")
    screen = Hiiro::TaskScreen.new(ops:)
    press(screen, "N")
    type(screen, "x y")

    assert_equal "bad name  1/2", frame(screen).last
  end

  def test_u_saves_the_current_task_through_ops
    screen = screen_for
    press(screen, "j", "u")

    assert_equal [[:save_current, "beta"]], @ops.calls
    assert_equal "current task: beta  2/2", frame(screen).last
  end

  def test_s_opens_the_workspace_and_finishes_the_screen
    screen = screen_for
    press(screen, "j")

    assert_equal true, screen.handle_key("s")
    assert_equal [[:open_workspace, "beta"]], @ops.calls
  end

  def test_ops_wraps_task_cli_commands_without_printing
    ops = Hiiro::TaskScreen::Ops.new
    Dir.mktmpdir do |home|
      ENV["HOME"] = home
      created = nil
      out, = capture_io { created = ops.create("delta") }

      assert_equal "", out
      assert_equal ["delta", "delta", "active"], created.values.values_at(:name, :session, :status)
      assert Dir.exist?(File.join(home, "notes", "work", "delta"))

      ops.save_current(created)

      assert_equal created.id.to_s, Hiiro::Table.named("t").find("current_task").value
    end
  end
end
