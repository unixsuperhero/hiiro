require "test_helper"
require "hiiro/todo"

class TodoItemTest < Minitest::Test
  def test_initialize_with_text_only
    item = Hiiro::TodoItem.new(text: "Buy milk")

    assert_equal "Buy milk", item.text
    assert_equal "not_started", item.status
    assert_nil item.tags
    refute_nil item.id
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
  include TestHelpers

  def setup
    @temp_dir = Dir.mktmpdir
    @todo_file = File.join(@temp_dir, "todo.yml")
    @manager = Hiiro::TodoManager.new(file_path: @todo_file)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_initialize_with_empty_file
    assert_equal [], @manager.all
  end

  def test_initialize_loads_existing_items
    data = {
      'todos' => [
        { 'id' => 'abc', 'text' => 'Existing task', 'status' => 'not_started' }
      ]
    }
    File.write(@todo_file, YAML.dump(data))

    manager = Hiiro::TodoManager.new(file_path: @todo_file)
    assert_equal 1, manager.all.length
    assert_equal 'Existing task', manager.all.first.text
  end

  def test_add_creates_item_and_saves
    item = @manager.add("New task", tags: "test")

    assert_equal "New task", item.text
    assert_equal "test", item.tags
    assert File.exist?(@todo_file)

    # Reload and verify persistence
    reloaded = Hiiro::TodoManager.new(file_path: @todo_file)
    assert_equal 1, reloaded.all.length
    assert_equal "New task", reloaded.all.first.text
  end

  def test_add_with_task_info
    task_info = { task_name: "feature", tree: "feature-tree" }
    item = @manager.add("Task with context", task_info: task_info)

    assert_equal "feature", item.task_name
    assert_equal "feature-tree", item.tree
  end

  def test_find_by_id
    item = @manager.add("Find me")
    found = @manager.find(item.id)

    assert_equal item.text, found.text
  end

  def test_find_by_id_prefix
    item = @manager.add("Find me")
    prefix = item.id[0..3]
    found = @manager.find(prefix)

    assert_equal item.text, found.text
  end

  def test_find_by_index
    @manager.add("First")
    @manager.add("Second")

    found = @manager.find_by_index(1)
    assert_equal "Second", found.text
  end

  def test_remove_by_index
    @manager.add("First")
    @manager.add("Second")

    removed = @manager.remove(0)

    assert_equal "First", removed.text
    assert_equal 1, @manager.all.length
    assert_equal "Second", @manager.all.first.text
  end

  def test_change_updates_item
    item = @manager.add("Original")

    @manager.change(0, text: "Updated", tags: "new-tag")

    assert_equal "Updated", item.text
    assert_equal "new-tag", item.tags
  end

  def test_start_changes_status
    item = @manager.add("Task")
    @manager.start(0)

    assert_equal "started", item.status
  end

  def test_done_changes_status
    item = @manager.add("Task")
    @manager.done(0)

    assert_equal "done", item.status
  end

  def test_skip_changes_status
    item = @manager.add("Task")
    @manager.skip(0)

    assert_equal "skip", item.status
  end

  def test_reset_changes_status
    item = @manager.add("Task")
    @manager.start(0)
    @manager.reset(0)

    assert_equal "not_started", item.status
  end

  def test_search
    @manager.add("Fix login bug")
    @manager.add("Add signup feature")
    @manager.add("Update login tests")

    results = @manager.search("login")

    assert_equal 2, results.length
    assert results.all? { |item| item.text.downcase.include?("login") }
  end

  def test_filter_by_status
    @manager.add("Not started")
    item2 = @manager.add("Started")
    @manager.start(1)
    item3 = @manager.add("Done")
    @manager.done(2)

    results = @manager.filter_by_status("started", "done")

    assert_equal 2, results.length
  end

  def test_filter_by_tag
    @manager.add("Tagged", tags: "urgent")
    @manager.add("Not tagged")

    results = @manager.filter_by_tag("urgent")

    assert_equal 1, results.length
    assert_equal "Tagged", results.first.text
  end

  def test_filter_by_task
    @manager.add("Task 1", task_info: { task_name: "feature" })
    @manager.add("Task 2", task_info: { task_name: "bugfix" })

    results = @manager.filter_by_task("feature")

    assert_equal 1, results.length
    assert_equal "Task 1", results.first.text
  end

  def test_active_returns_not_started_and_started
    @manager.add("Not started")
    @manager.add("Started")
    @manager.start(1)
    @manager.add("Done")
    @manager.done(2)

    results = @manager.active

    assert_equal 2, results.length
  end

  def test_completed_returns_done_and_skip
    @manager.add("Active")
    @manager.add("Done")
    @manager.done(1)
    @manager.add("Skipped")
    @manager.skip(2)

    results = @manager.completed

    assert_equal 2, results.length
  end

  def test_list_returns_formatted_string
    @manager.add("First task")
    @manager.add("Second task")

    output = @manager.list

    assert_includes output, "First task"
    assert_includes output, "Second task"
    assert_includes output, "[ ]"  # not_started icon
  end

  def test_list_shows_status_icons
    @manager.add("Not started")
    @manager.add("Started")
    @manager.start(1)
    @manager.add("Done")
    @manager.done(2)
    @manager.add("Skipped")
    @manager.skip(3)

    output = @manager.list(show_all: true)

    assert_includes output, "[ ]"  # not_started
    assert_includes output, "[>]"  # started
    assert_includes output, "[x]"  # done
    assert_includes output, "[-]"  # skip
  end

  def test_list_empty_returns_message
    output = @manager.list

    assert_equal "No todo items found.", output
  end

  def test_format_item_includes_tags
    item = @manager.add("Task", tags: "urgent")
    output = @manager.format_item(item, 0)

    assert_includes output, "[urgent]"
  end

  def test_format_item_includes_task_name
    item = @manager.add("Task", task_info: { task_name: "feature" })
    output = @manager.format_item(item, 0)

    assert_includes output, "(feature)"
  end
end
