require_relative '../test_helper'

class ReminderTest < Minitest::Test
  Reminder = Hiiro::Reminder
  NOW = Time.iso8601('2026-10-12T12:00:00Z')

  def setup
    [Reminder, Hiiro::JobClaim, Hiiro::JobOutcome].each { |model| model.dataset.delete }
  end

  def teardown
    Reminder.dataset.delete
  end

  def add(message = 'Take a break', **fields)
    Reminder.add(message: message, created_at: '2026-10-01T10:00:00Z', **fields)
  end

  def test_pause_resume_and_remove_preserve_other_fields_and_stable_identity
    first = add
    stale = Reminder[first.id]
    second = add('Other writer')
    Reminder[first.id].update(message: 'New message', last_triggered: NOW.iso8601, sound: 'basso')
    Reminder.set_enabled(stale.id, false)
    assert_equal ['New message', NOW.iso8601, 'basso', false], Reminder[first.id].values.values_at(:message, :last_triggered, :sound, :enabled)
    Reminder.set_enabled(stale.id, true)
    Reminder.remove(second.id)
    assert_equal [[first.id, 'New message', true]], Reminder.order(:id).all.map { |row| [row.id, row.message, row.enabled] }
  end

  def test_stale_edit_changes_only_edited_fields_and_preserves_checkpoint_pause_and_new_rows
    first = add(sound: 'basso')
    baseline = [first.values.dup]
    second = add('Concurrent addition')
    Reminder.mark_triggered(first.id, now: NOW, expected_checkpoint: first.schedule_checkpoint)
    Reminder.set_enabled(first.id, false)
    Reminder.apply_edit(baseline: baseline, rows: [baseline.first.merge(message: 'Edited message', sound: nil)])
    assert_equal [first.id, 'Edited message', '1h', nil, false, false, nil, NOW.iso8601, '2026-10-01T10:00:00Z'], Reminder[first.id].values.values_at(:id, *Reminder::FIELDS)
    assert_equal 'Concurrent addition', Reminder[second.id].message
  end

  def test_deleting_selected_rows_does_not_delete_concurrent_additions
    first = add('Selected')
    baseline = [first.values.dup]
    second = add('Unselected')
    Reminder.apply_edit(baseline: baseline, rows: [])
    assert_equal [[second.id, 'Unselected']], Reminder.all.map { |row| [row.id, row.message] }
  end

  def test_field_conflict_rolls_back_new_rows_and_prior_edits
    first = add('First')
    second = add('Second')
    baseline = [first.values.dup, second.values.dup]
    Reminder[second.id].update(message: 'Concurrent message')
    assert_raises(Reminder::EditConflict) do
      Reminder.apply_edit(baseline: baseline, rows: [{ message: 'New row' }, { id: first.id, message: 'Changed first' }, { id: second.id, message: 'Changed second' }])
    end
    assert_equal [[first.id, 'First'], [second.id, 'Concurrent message']], Reminder.order(:id).all.map { |row| [row.id, row.message] }
  end

  def test_concurrent_checkpoint_blocks_deletion_and_rolls_back_edit
    first = add('First')
    second = add('Second')
    baseline = [first.values.dup, second.values.dup]
    Reminder.mark_triggered(second.id, now: NOW, expected_checkpoint: second.schedule_checkpoint)
    assert_raises(Reminder::EditConflict) do
      Reminder.apply_edit(baseline: baseline, rows: [{ id: first.id, message: 'Changed first' }])
    end
    assert_equal [[first.id, 'First', nil], [second.id, 'Second', NOW.iso8601]], Reminder.order(:id).all.map { |row| [row.id, row.message, row.last_triggered] }
  end

  def test_edit_never_resurrects_a_deleted_reminder
    first = add('Removed')
    baseline = [first.values.dup]
    Reminder.remove(first.id)
    survivor = add('Survivor')
    assert_raises(Reminder::EditConflict) { Reminder.apply_edit(baseline: baseline, rows: [{ id: first.id, message: 'Stale edit' }]) }
    assert_equal [[survivor.id, 'Survivor']], Reminder.all.map { |row| [row.id, row.message] }
  end

  def test_invalid_duplicate_and_unknown_ids_leave_the_batch_unchanged
    first = add
    baseline = [first.values.dup]
    [ [{ id: first.id, message: 'Change' }, { id: first.id }],
      [{ id: first.id + 100, message: 'Unknown' }],
      [{ id: first.id.to_s, message: 'String ID' }],
      [{ id: first.id, message: 'Change' }, { message: 'Invalid', enabled: 'false' }],
      [{ id: first.id, message: 'Change' }, { message: 'Invalid', trigger_at: 'not a date' }] ].each do |rows|
      assert_raises(ArgumentError) { Reminder.apply_edit(baseline: baseline, rows: rows) }
      assert_equal [[first.id, 'Take a break', true]], Reminder.all.map { |row| [row.id, row.message, row.enabled] }
    end
  end

  def test_recurring_and_one_time_due_checks_preserve_fields_and_disable_only_once
    recurring = add('Recurring', interval: '30m', sound: 'basso')
    once = add('Once', interval: nil, once: true, trigger_at: '2026-10-12T11:59:00Z')
    future = add('Future', once: true, trigger_at: '2026-10-12T13:00:00Z')
    paused = add('Paused', enabled: false)
    delivered = []
    triggered = Reminder.check_due(now: NOW, deliver: ->(row) { delivered << [row.id, row.message, row.sound] })
    assert_equal [[recurring.id, 'Recurring', 'basso'], [once.id, 'Once', nil]], delivered
    assert_equal [[recurring.id, 'completed', 'delivered'], [once.id, 'completed', 'delivered']],
      triggered.map { |row, outcome| [row.id, outcome.outcome, outcome.detail] }
    assert_equal [NOW.iso8601, true, '30m', 'basso'], Reminder[recurring.id].values.values_at(:last_triggered, :enabled, :interval, :sound)
    assert_equal [NOW.iso8601, false, nil, '2026-10-12T11:59:00Z'], Reminder[once.id].values.values_at(:last_triggered, :enabled, :interval, :trigger_at)
    assert_equal [false, true], [Reminder[recurring.id].due?(now: NOW + 1799), Reminder[recurring.id].due?(now: NOW + 1800)]
    assert_equal 1, Reminder.clean
    assert_equal [recurring.id, future.id, paused.id], Reminder.order(:id).select_map(:id)
  end

  def test_stale_due_check_cannot_override_pause_schedule_or_deletion
    first = add
    expected = first.schedule_checkpoint
    Reminder.set_enabled(first.id, false)
    assert_nil Reminder.mark_triggered(first.id, now: NOW, expected_checkpoint: expected)
    Reminder.set_enabled(first.id, true)
    Reminder[first.id].update(interval: '2h')
    assert_nil Reminder.mark_triggered(first.id, now: NOW, expected_checkpoint: expected)
    assert_equal [false, '2h', nil], [Reminder[first.id].one_time?, Reminder[first.id].interval, Reminder[first.id].last_triggered]
    Reminder.remove(first.id)
    assert_nil Reminder.mark_triggered(first.id, now: NOW, expected_checkpoint: expected)
    survivor = add('Survivor')
    assert_equal [[survivor.id, 'Survivor']], Reminder.all.map { |row| [row.id, row.message] }
  end

  def test_failed_delivery_is_recorded_as_failed_and_retried_without_advancing_checkpoint
    row = add
    failed = Reminder.check_due(now: NOW, deliver: ->(_) { false })
    assert_equal [[row.id, 'failed', 'notification delivery failed; retried on the next check', 1]],
      failed.map { |current, outcome| [current.id, outcome.outcome, outcome.detail, outcome.attempt] }
    assert_equal [row.id, nil, true], Reminder[row.id].values.values_at(:id, :last_triggered, :enabled)
    assert_raises(RuntimeError) { Reminder.check_due(now: NOW, deliver: ->(_) { raise 'Adapter failed' }) }
    assert_equal ['failed', 'RuntimeError: Adapter failed'], Hiiro::JobOutcome.order(:id).last.values.values_at(:outcome, :detail)
    delivered = Reminder.check_due(now: NOW, deliver: ->(_) { true })
    assert_equal [['completed', 3]], delivered.map { |_row, outcome| [outcome.outcome, outcome.attempt] }
    assert_equal NOW.iso8601, Reminder[row.id].last_triggered
    assert_equal [["reminder:#{row.id}", "first:2026-10-01T10:00:00Z", 3, 'completed']],
      Hiiro::JobClaim.select_map(%i[definition occurrence attempt outcome])
  end

  def test_overlapping_check_skips_an_occurrence_another_live_worker_holds
    row = add('Held', once: true, interval: nil, trigger_at: '2026-10-12T11:59:00Z')
    Hiiro::Job.claim("reminder:#{row.id}", '2026-10-12T11:59:00Z', run_id: 'run-other', now: NOW)
    delivered = []
    skipped = Reminder.check_due(now: NOW, deliver: ->(current) { delivered << current.id })
    assert_equal [], delivered
    assert_equal [['skipped-overlap', 'occurrence held by run-other']], skipped.map { |_row, outcome| outcome.values.values_at(:outcome, :detail) }
    assert_equal [nil, true], Reminder[row.id].values.values_at(:last_triggered, :enabled)
  end

  def test_reloaded_due_one_time_and_recurring_reminders_are_claimed_once
    once = add('Once', once: true, interval: nil, trigger_at: '2026-10-12T11:59:00Z')
    recurring = add('Recurring', interval: '30m', last_triggered: '2026-10-12T11:30:00Z')
    delivered = []
    deliver = ->(row) { delivered << row.id }
    stale_rows = Reminder.due(now: NOW)
    Reminder.check_due(now: NOW, deliver: deliver)
    assert_equal [], Reminder.check_due(now: NOW + 5, deliver: deliver)
    # A worker that loaded the rows before the first check finished still claims nothing.
    stale_rows.each { |row| assert_nil Hiiro::Job.perform("reminder:#{row.id}", row.occurrence, now: NOW) { flunk 'claimed twice' } }
    assert_equal [once.id, recurring.id], delivered
    assert_equal [["reminder:#{once.id}", '2026-10-12T11:59:00Z'], ["reminder:#{recurring.id}", '2026-10-12T12:00:00Z']],
      Hiiro::JobClaim.order(:id).select_map(%i[definition occurrence])
    assert_equal '2026-10-12T12:30:00Z', Reminder[recurring.id].occurrence
  end

  def test_legacy_invalid_interval_and_checkpoint_keep_the_recurrence_fallback
    row = add(interval: 'unknown', last_triggered: '2026-10-12T11:00:00Z')
    assert_equal [false, true], [row.due?(now: NOW - 1), row.due?(now: NOW)]
    Reminder[row.id].update(last_triggered: 'invalid old timestamp')
    assert_equal [row.id], Reminder.due(now: NOW).map(&:id)
  end

  def test_calendar_digits_are_not_interpreted_as_unix_milliseconds
    once, at, interval = Reminder.parse_time_arg('202610131430', now: NOW)
    assert_equal true, once
    assert_equal '2026-10-13 14:30', Time.iso8601(at).strftime('%Y-%m-%d %H:%M')
    assert_nil interval
    assert_equal [true, '2026-10-12T12:15:00Z', '15m'], Reminder.parse_time_arg('15m', now: NOW)
  end

  def editor(result: true, &change)
    Object.new.tap do |hiiro|
      hiiro.define_singleton_method(:edit_files) do |path|
        change.call(path) if change
        result
      end
    end
  end

  def test_editor_failure_blank_and_unchanged_output_do_not_mutate_database
    row = add
    [editor, editor { |path| File.write(path, '') }, editor(result: false) { |path| File.write(path, '[]') }].each do |hiiro|
      assert_equal false, Reminder.edit(hiiro: hiiro, reminders: [Reminder[row.id]])
      assert_equal [[row.id, 'Take a break', true]], Reminder.all.map { |current| [current.id, current.message, current.enabled] }
    end
    good_editor = editor { |path| File.write(path, [{ 'id' => row.id, 'message' => 'Edited through InputFile' }].to_yaml) }
    assert_equal true, Reminder.edit(hiiro: good_editor, reminders: [Reminder[row.id]])
    assert_equal 'Edited through InputFile', Reminder[row.id].message
  end

  def test_unedited_legacy_values_survive_a_message_edit
    row = add
    Reminder[row.id].update(last_triggered: 'invalid legacy checkpoint', created_at: nil)
    baseline = [Reminder[row.id].values.dup]
    Reminder.apply_edit(baseline: baseline, rows: [baseline.first.merge(message: 'Updated legacy reminder')])
    assert_equal ['Updated legacy reminder', 'invalid legacy checkpoint', nil], Reminder[row.id].values.values_at(:message, :last_triggered, :created_at)
  end

  def test_invalid_editor_yaml_and_invalid_rows_do_not_apply_partial_edits
    row = add
    invalid_yaml = editor { |path| File.write(path, "[broken") }
    assert_raises(Psych::Exception) { Reminder.edit(hiiro: invalid_yaml, reminders: [Reminder[row.id]]) }
    invalid_rows = editor do |path|
      File.write(path, [{ 'id' => row.id, 'message' => 'Partial edit' }, { 'message' => 'Bad', 'once' => 'yes' }].to_yaml)
    end
    assert_raises(ArgumentError) { Reminder.edit(hiiro: invalid_rows, reminders: [Reminder[row.id]]) }
    assert_equal [[row.id, 'Take a break', true]], Reminder.all.map { |current| [current.id, current.message, current.enabled] }
  end
end
