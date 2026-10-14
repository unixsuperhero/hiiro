require "test_helper"

class TaskRecordRulesTest < Minitest::Test
  def setup = Hiiro::TaskRecord.dataset.delete
  def teardown = Hiiro::TaskRecord.dataset.delete

  def fields(task, *names) = task.refresh.values.values_at(*names)

  def test_create_task_sets_session_status_and_timestamps
    task = Hiiro::TaskRecord.create_task("alpha")

    assert_equal ["alpha", "alpha", "active"], fields(task, :name, :session, :status)
    refute_nil task.created_at
    assert_equal task.created_at, task.updated_at
  end

  def test_set_next_sets_and_clears_on_nil_or_empty
    task = Hiiro::TaskRecord.create(name: "alpha")
    task.set_next!("ship")

    assert_equal "ship", fields(task, :next_action).first
    refute_nil task.updated_at

    task.set_next!("")
    assert_nil fields(task, :next_action).first

    task.set_next!("ship")
    task.set_next!(nil)
    assert_nil fields(task, :next_action).first
  end

  def test_set_waiting_moves_to_waiting_and_clearing_returns_to_active
    task = Hiiro::TaskRecord.create(name: "alpha", status: "done", completed_at: "c", archived_at: "a")
    task.set_waiting!("review")

    assert_equal ["review", "waiting", nil, nil], fields(task, :waiting_on, :status, :completed_at, :archived_at)

    task.set_waiting!("")
    assert_equal [nil, "active"], fields(task, :waiting_on, :status)
  end

  def test_clearing_waiting_on_a_non_waiting_task_keeps_its_status
    task = Hiiro::TaskRecord.create(name: "alpha", status: "done", waiting_on: "x")
    task.set_waiting!(nil)

    assert_equal [nil, "done"], fields(task, :waiting_on, :status)
  end

  def test_set_status_applies_timestamp_rules
    task = Hiiro::TaskRecord.create(name: "alpha", status: "active")
    task.set_status!("done")
    completed = task.completed_at

    refute_nil completed
    assert_equal ["done", nil], fields(task, :status, :archived_at)

    task.set_status!("done")
    assert_equal completed, task.completed_at

    task.set_status!("archived")
    refute_nil task.archived_at
    assert_equal completed, task.completed_at

    task.set_status!("active")
    assert_equal ["active", nil, nil], fields(task, :status, :completed_at, :archived_at)
  end

  def test_set_status_rejects_unknown_states
    task = Hiiro::TaskRecord.create(name: "alpha")
    error = assert_raises(Hiiro::Error) { task.set_status!("bogus") }

    assert_equal "Status must be active, waiting, done, archived", error.message
  end
end
