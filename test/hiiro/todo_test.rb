require "test_helper"
require "hiiro/todo"

class TodoItemTest < Minitest::Test
  def test_initialize_with_text_only
    item = Hiiro::TodoItem.new(text: "Buy milk")

    assert_equal "Buy milk", item.text
    assert_equal "not_started", item.status
    assert_nil item.tags
    assert_nil item.id  # ID is assigned by TodoManager, not TodoItem
    refute_nil item.created_at
  end

  def test_initialize_with_all_options
    item = Hiiro::TodoItem.new(
      id: "abc123",
      text: "Task text",
      status: "started",
      tags: "urgent, work",
      task_name: "feature",
      subtask_name: "impl",
      tree: "feature-tree",
      branch: "feature-branch",
      session: "work"
    )

    assert_equal "abc123", item.id
    assert_equal "Task text", item.text
    assert_equal "started", item.status
    assert_equal "urgent, work", item.tags
    assert_equal "feature", item.task_name
    assert_equal "impl", item.subtask_name
    assert_equal "feature-tree", item.tree
    assert_equal "feature-branch", item.branch
    assert_equal "work", item.session
  end

  def test_initialize_invalid_status_defaults_to_not_started
    item = Hiiro::TodoItem.new(text: "Test", status: "invalid")

    assert_equal "not_started", item.status
  end

  def test_tags_list_returns_array
    item = Hiiro::TodoItem.new(text: "Test", tags: "tag1, tag2, tag3")

    assert_equal ["tag1", "tag2", "tag3"], item.tags_list
  end

  def test_tags_list_returns_empty_array_when_nil
    item = Hiiro::TodoItem.new(text: "Test")

    assert_equal [], item.tags_list
  end

  def test_has_tag_returns_true_for_existing_tag
    item = Hiiro::TodoItem.new(text: "Test", tags: "urgent, work")

    assert item.has_tag?("urgent")
    assert item.has_tag?("URGENT")  # case insensitive
  end

  def test_has_tag_returns_false_for_missing_tag
    item = Hiiro::TodoItem.new(text: "Test", tags: "work")

    refute item.has_tag?("urgent")
  end

  def test_add_tag
    item = Hiiro::TodoItem.new(text: "Test", tags: "existing")
    item.add_tag("new")

    assert_includes item.tags_list, "new"
    assert_includes item.tags_list, "existing"
  end

  def test_add_tag_ignores_duplicates
    item = Hiiro::TodoItem.new(text: "Test", tags: "existing")
    item.add_tag("EXISTING")  # case insensitive duplicate

    assert_equal 1, item.tags_list.length
  end

  def test_remove_tag
    item = Hiiro::TodoItem.new(text: "Test", tags: "keep, remove")
    item.remove_tag("remove")

    assert_includes item.tags_list, "keep"
    refute_includes item.tags_list, "remove"
  end

  def test_has_task_info
    item_with_task = Hiiro::TodoItem.new(text: "Test", task_name: "feature")
    item_with_subtask = Hiiro::TodoItem.new(text: "Test", subtask_name: "impl")
    item_without = Hiiro::TodoItem.new(text: "Test")

    assert item_with_task.has_task_info?
    assert item_with_subtask.has_task_info?
    refute item_without.has_task_info?
  end

  def test_full_task_name
    item = Hiiro::TodoItem.new(text: "Test", task_name: "feature", subtask_name: "impl")
    assert_equal "feature/impl", item.full_task_name

    item_no_subtask = Hiiro::TodoItem.new(text: "Test", task_name: "feature")
    assert_equal "feature", item_no_subtask.full_task_name

    item_no_task = Hiiro::TodoItem.new(text: "Test")
    assert_nil item_no_task.full_task_name
  end

  def test_update_status
    item = Hiiro::TodoItem.new(text: "Test")

    result = item.update_status("started")

    assert result
    assert_equal "started", item.status
    refute_nil item.updated_at
  end

  def test_update_status_rejects_invalid_status
    item = Hiiro::TodoItem.new(text: "Test")
    result = item.update_status("invalid")

    refute result
    assert_equal "not_started", item.status
  end

  def test_to_h
    item = Hiiro::TodoItem.new(
      id: "abc123",
      text: "Test task",
      status: "started",
      tags: "urgent"
    )

    h = item.to_h

    assert_equal "abc123", h['id']
    assert_equal "Test task", h['text']
    assert_equal "started", h['status']
    assert_equal "urgent", h['tags']
  end

  def test_to_h_excludes_nil_optional_fields
    item = Hiiro::TodoItem.new(text: "Test")
    h = item.to_h

    refute h.key?('tags')
    refute h.key?('task_name')
    refute h.key?('tree')
  end

  def test_from_h
    h = {
      'id' => 'xyz789',
      'text' => 'Restored task',
      'status' => 'done',
      'tags' => 'complete',
      'task_name' => 'feature'
    }

    item = Hiiro::TodoItem.from_h(h)

    assert_equal 'xyz789', item.id
    assert_equal 'Restored task', item.text
    assert_equal 'done', item.status
    assert_equal 'complete', item.tags
    assert_equal 'feature', item.task_name
  end

  def test_roundtrip_to_h_from_h
    original = Hiiro::TodoItem.new(
      text: "Roundtrip test",
      status: "started",
      tags: "test, roundtrip",
      task_name: "feature",
      tree: "tree-name"
    )

    restored = Hiiro::TodoItem.from_h(original.to_h)

    assert_equal original.id, restored.id
    assert_equal original.text, restored.text
    assert_equal original.status, restored.status
    assert_equal original.tags, restored.tags
    assert_equal original.task_name, restored.task_name
    assert_equal original.tree, restored.tree
  end

  def test_match_by_text
    item = Hiiro::TodoItem.new(text: "Fix the login bug")

    assert item.match?("login")
    assert item.match?("LOGIN")  # case insensitive
    refute item.match?("signup")
  end

  def test_match_by_tags
    item = Hiiro::TodoItem.new(text: "Task", tags: "urgent, backend")

    assert item.match?("urgent")
    refute item.match?("frontend")
  end

  def test_match_by_task_name
    item = Hiiro::TodoItem.new(text: "Task", task_name: "feature-auth")

    assert item.match?("auth")
  end
end

class TodoManagerTest < Minitest::Test
  def setup
    Hiiro::TodoItem.dataset.delete
    @manager = Hiiro::TodoManager.new
  end

  def editor(&block)
    Object.new.tap do |instance|
      instance.define_singleton_method(:edit_files) do |path|
        block.call(path)
        true
      end
    end
  end

  def test_stale_manager_edit_preserves_external_insert_and_context
    Hiiro::TodoItem.create(id: 1, text: 'original', task_name: 'feature', subtask_name: 'child', tree: 'tree', branch: 'branch', session: 'session', tags: 'old')
    stale = Hiiro::TodoManager.new
    stale.all
    Hiiro::TodoItem.create(id: 2, text: 'external')
    stale.change(1, text: 'edited')
    assert_equal [[1, 'edited'], [2, 'external']], @manager.all.map { |item| [item.id, item.text] }
    assert_equal ['feature', 'child', 'tree', 'branch', 'session', 'old'], Hiiro::TodoItem[1].values.values_at(:task_name, :subtask_name, :tree, :branch, :session, :tags)
  end

  def test_interleaved_managers_insert_database_ids_and_remove_only_selected_row
    first = @manager.add('first')
    stale = Hiiro::TodoManager.new
    stale.all
    second = @manager.add('second')
    third = stale.add('third')
    assert_equal [first.id + 1, first.id + 2], [second.id, third.id]
    stale.remove(first.id)
    assert_equal [[second.id, 'second'], [third.id, 'third']], @manager.all.map { |item| [item.id, item.text] }
    stale.remove(third.id)
    fourth = @manager.add('fourth')
    assert_equal third.id + 1, fourth.id
  end

  def test_change_preserves_external_fields_and_explicit_null_clears_tags
    item = @manager.add('first', tags: 'old')
    @manager.all
    Hiiro::TodoItem[item.id].update(tags: 'external', branch: 'new-branch')
    @manager.change(item.id, text: 'edited')
    assert_equal ['edited', 'external', 'new-branch'], Hiiro::TodoItem[item.id].values.values_at(:text, :tags, :branch)
    @manager.change(item.id, tags: nil)
    assert_equal ['edited', nil, 'new-branch'], Hiiro::TodoItem[item.id].values.values_at(:text, :tags, :branch)
  end

  def test_status_transitions_and_filters
    pending = @manager.add('pending')
    started = @manager.add('started', tags: 'urgent', task_info: { task_name: 'feature' })
    done = @manager.add('done')
    skipped = @manager.add('skipped')
    @manager.start(started.id)
    @manager.done(done.id)
    @manager.skip(skipped.id)
    assert_equal ['pending', 'started'], @manager.active.map(&:text)
    assert_equal ['done', 'skipped'], @manager.completed.map(&:text)
    assert_equal ['started'], @manager.filter_by_tag('URGENT').map(&:text)
    assert_equal ['started'], @manager.filter_by_task('feature').map(&:text)
    assert_equal ['pending'], @manager.search('pend').map(&:text)
    @manager.reset(done.id)
    assert_equal 'not_started', Hiiro::TodoItem[done.id].status
    assert_equal "#{started.id} [>] started  [urgent]  (feature)", @manager.format_item(Hiiro::TodoItem[started.id])
    assert_equal 'pending', @manager.find(pending.id).text
    assert_equal 'started', @manager.find_by_index(1).text
  end

  def test_editor_preserves_ids_context_and_concurrent_unedited_fields
    item = @manager.add('original', tags: 'old', task_info: { task_name: 'feature', subtask_name: 'child', tree: 'tree', branch: 'branch', session: 'session' })
    original_created_at = item.created_at
    selected = @manager.all
    edit = editor do |path|
      rows = YAML.safe_load_file(path)
      rows.first['text'] = 'edited'
      Hiiro::TodoItem[item.id].update(tags: 'external', status: 'started')
      Hiiro::TodoItem.create(text: 'concurrent')
      File.write(path, rows.to_yaml)
    end
    @manager.edit_items(selected, hiiro: edit)
    reloaded = Hiiro::TodoItem[item.id]
    assert_equal ['edited', 'external', 'started', 'feature', 'child', 'tree', 'branch', 'session', original_created_at], reloaded.values.values_at(:text, :tags, :status, :task_name, :subtask_name, :tree, :branch, :session, :created_at)
    assert_equal ['edited', 'concurrent'], @manager.all.map(&:text)
  end

  def test_editor_missing_keys_preserve_values_and_new_rows_get_ids
    item = @manager.add('original', tags: 'old')
    edit = editor { |path| File.write(path, [{ 'id' => item.id, 'tags' => nil }, { 'text' => 'new' }].to_yaml) }
    @manager.edit_items(item, hiiro: edit)
    assert_equal [[item.id, 'original', nil], [item.id + 1, 'new', nil]], @manager.all.map { |row| [row.id, row.text, row.tags] }
  end

  def test_editor_deletes_only_baseline_selection
    selected = @manager.add('selected')
    other = @manager.add('other')
    edit = editor do |path|
      Hiiro::TodoItem.create(text: 'external')
      File.write(path, '[]')
    end
    @manager.edit_items([selected], hiiro: edit)
    assert_equal [[other.id, 'other'], [other.id + 1, 'external']], @manager.all.map { |row| [row.id, row.text] }
  end

  def test_editor_conflict_rolls_back_deletions_and_insertions
    first = @manager.add('first')
    second = @manager.add('second')
    edit = editor do |path|
      Hiiro::TodoItem[second.id].update(text: 'external')
      File.write(path, [{ 'text' => 'new' }, { 'id' => second.id, 'text' => 'edited' }].to_yaml)
    end
    assert_raises(Hiiro::TodoManager::EditConflict) { @manager.edit_items(@manager.all, hiiro: edit) }
    assert_equal [[first.id, 'first'], [second.id, 'external']], @manager.all.map { |row| [row.id, row.text] }
  end

  def test_editor_refuses_concurrently_changed_deletion_and_removed_edit
    item = @manager.add('first')
    edit = editor do |path|
      Hiiro::TodoItem[item.id].update(branch: 'external')
      File.write(path, '[]')
    end
    assert_raises(Hiiro::TodoManager::EditConflict) { @manager.edit_items(@manager.all, hiiro: edit) }
    assert_equal 'external', Hiiro::TodoItem[item.id].branch
    edit = editor do |path|
      Hiiro::TodoItem[item.id].delete
      File.write(path, [{ 'id' => item.id, 'text' => 'edited' }].to_yaml)
    end
    assert_raises(Hiiro::TodoManager::EditConflict) { @manager.edit_items(@manager.all, hiiro: edit) }
    assert_nil Hiiro::TodoItem[item.id]
  end

  def test_editor_rejects_invalid_duplicate_and_unknown_ids_before_writing
    item = @manager.add('original')
    invalid = [[{ 'id' => item.id, 'text' => 'edited' }, { 'id' => item.id }], [{ 'id' => item.id + 1, 'text' => 'new' }], [{ 'id' => item.id.to_s, 'text' => 'edited' }], [{ 'text' => 'new', 'status' => 'bad' }], [{ 'id' => item.id, 'tags' => false }]]
    invalid.each do |rows|
      edit = editor { |path| File.write(path, rows.to_yaml) }
      assert_raises(ArgumentError) { @manager.edit_items(@manager.all, hiiro: edit) }
      assert_equal [[item.id, 'original']], @manager.all.map { |row| [row.id, row.text] }
    end
  end

  def test_unchanged_blank_and_invalid_editor_documents_do_not_write
    item = @manager.add('original')
    unchanged = editor { |_path| Hiiro::TodoItem[item.id].update(text: 'external') }
    @manager.edit_items(@manager.all, hiiro: unchanged)
    blank = editor { |path| File.write(path, '') }
    @manager.edit_items(@manager.all, hiiro: blank)
    invalid = editor { |path| File.write(path, '[') }
    assert_raises(ArgumentError) { @manager.edit_items(@manager.all, hiiro: invalid) }
    assert_equal [[item.id, 'external']], @manager.all.map { |row| [row.id, row.text] }
  end

  def test_failed_editor_cannot_apply_valid_but_cancelled_document
    item = @manager.add('original')
    failed = Object.new
    failed.define_singleton_method(:edit_files) do |path|
      File.write(path, [{ 'id' => item.id, 'text' => 'cancelled' }].to_yaml)
      false
    end
    assert_raises(ArgumentError) { @manager.edit_items(@manager.all, hiiro: failed) }
    assert_equal [[item.id, 'original']], @manager.all.map { |row| [row.id, row.text] }
  end

  def test_editor_additions_are_unsaved_until_insert_and_reject_explicit_ids
    edit = editor { |path| File.write(path, [{ 'text' => 'new', 'tags' => 'urgent' }].to_yaml) }
    rows = @manager.edit_items(task_info: { task_name: 'feature' }, hiiro: edit)
    assert_nil rows.first.id
    @manager.add_items(rows)
    assert_equal [['new', 'urgent', 'feature']], @manager.all.map { |row| [row.text, row.tags, row.task_name] }
    assert_raises(ArgumentError) { @manager.add_items([Hiiro::TodoItem.new(id: 999, text: 'invalid')]) }
    assert_equal ['new'], @manager.all.map(&:text)
  end
end
