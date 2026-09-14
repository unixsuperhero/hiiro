require_relative "../test_helper"

class CurrentTaskTest < Minitest::Test
  def setup
    Hiiro::TaskResource.dataset.delete
    Hiiro::TaskRecord.dataset.delete
    Hiiro::PinRecord.dataset.delete
    @dir = File.realpath(Dir.mktmpdir("hiiro-current-task-"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_resolves_task_from_working_directory_inside_code_or_registered_directory
    code = File.join(@dir, "code")
    registered = File.join(@dir, "registered")
    FileUtils.mkdir_p([File.join(code, "deep"), registered])
    task = Hiiro::TaskRecord.create(name: "one", primary_directory: code)
    Hiiro::TaskRecord.create(name: "two")
    Hiiro::TaskResource.create(task_id: task.id, kind: "directory", target: registered)

    assert_equal "one", Hiiro::CurrentTask.new(cwd: File.join(code, "deep"), pin: false).resolve!.name
    assert_equal "one", Hiiro::CurrentTask.new(cwd: registered, pin: false).resolve!.name
    assert_nil Hiiro::CurrentTask.new(cwd: @dir, pin: false).resolve
  end

  def test_ambiguous_directory_raises_hiiro_error_and_resolve_returns_nil
    shared = File.join(@dir, "shared")
    FileUtils.mkdir_p(shared)
    Hiiro::TaskRecord.create(name: "a", primary_directory: shared)
    Hiiro::TaskRecord.create(name: "b", primary_directory: shared)

    error = assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: shared, pin: false).resolve! }
    assert_match(/ambiguous/i, error.message)
    assert_nil Hiiro::CurrentTask.new(cwd: shared, pin: false).resolve
  end

  def test_saved_pin_is_used_only_when_enabled
    task = Hiiro::TaskRecord.create(name: "pinned")
    Hiiro::PinRecord.create(command: "t", key: "current_task", value_json: task.id.to_s)

    assert_nil Hiiro::CurrentTask.new(cwd: @dir, pin: false).resolve
    assert_equal "pinned", Hiiro::CurrentTask.new(cwd: @dir, pin: true).resolve!.name
    error = assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: @dir, pin: false).resolve! }
    assert_match(/no current task/i, error.message)
  end
end
