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
    Hiiro::TaskResource.dataset.delete
    Hiiro::TaskRecord.dataset.delete
    Hiiro::PinRecord.dataset.delete
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

  def test_ambiguous_directory_raises_in_both_required_and_optional_resolution
    shared = File.join(@dir, "shared")
    FileUtils.mkdir_p(shared)
    Hiiro::TaskRecord.create(name: "a", primary_directory: shared)
    Hiiro::TaskRecord.create(name: "b", primary_directory: shared)

    error = assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: shared, pin: false).resolve! }
    assert_match(/ambiguous/i, error.message)
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: shared, pin: false).resolve }
  end

  def test_saved_pin_is_used_only_when_enabled
    task = Hiiro::TaskRecord.create(name: "pinned")
    Hiiro::PinRecord.create(command: "t", key: "current_task", value_json: task.id.to_s)

    assert_nil Hiiro::CurrentTask.new(cwd: @dir, pin: false).resolve
    assert_equal "pinned", Hiiro::CurrentTask.new(cwd: @dir, pin: true).resolve!.name
    error = assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: @dir, pin: false).resolve! }
    assert_match(/no current task/i, error.message)
  end

  def test_symlink_directory_and_nested_task_overlap
    code = File.join(@dir, 'code')
    nested = File.join(code, 'nested')
    FileUtils.mkdir_p(nested)
    File.symlink(code, File.join(@dir, 'alias'))
    task = Hiiro::TaskRecord.create(name: 'outer', primary_directory: code)
    resolver = Hiiro::CurrentTask.new(cwd: File.join(@dir, 'alias/nested'), pin: false, env: {})
    context = resolver.context
    assert_equal [task.id, code, :directory], [context.task.id, context.start_directory, context.task_source]
    Hiiro::TaskRecord.create(name: 'inner', primary_directory: nested)
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: nested, pin: false, env: {}).context }
    explicit = Hiiro::CurrentTask.new(task: task, cwd: nested, env: {}).context
    assert_equal ['outer', :explicit, code], [explicit.task.name, explicit.task_source, explicit.start_directory]
  end

  def test_stale_pin_is_an_error_but_explicit_task_bypasses_it
    task = Hiiro::TaskRecord.create(name: 'selected')
    Hiiro::PinRecord.set('t', 'current_task', 999999)
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(cwd: @dir, env: {}).resolve }
    context = Hiiro::CurrentTask.new(task: 'selected', cwd: @dir, env: {}).context
    assert_equal [task.id, :explicit], [context.task.id, context.task_source]
    assert_nil Hiiro::CurrentTask.new(cwd: @dir, pin: false, env: {}).resolve
  end

  def test_calling_workspace_precedes_directory_and_focus_is_not_inference
    directory_task = Hiiro::TaskRecord.create(name: 'directory', primary_directory: @dir)
    workspace_task = Hiiro::TaskRecord.create(name: 'workspace.dot')
    workspace = Struct.new(:id, :name).new('w1', 'workspace_dot')
    pane = Struct.new(:id, :workspace_id, :tab_id).new('p1', 'w1', nil)
    client = Object.new
    client.define_singleton_method(:server_running?) { true }
    client.define_singleton_method(:get_pane) { |id| id == 'p1' ? pane : nil }
    client.define_singleton_method(:get_workspace) { |id| id == 'w1' ? workspace : nil }
    env = { 'HERDR_PANE_ID' => 'p1' }
    context = Hiiro::CurrentTask.new(herdr: client, cwd: @dir, env: env, pin: false).context
    assert_equal [workspace_task.id, :workspace, 'w1', 'p1'],
                 [context.task.id, context.task_source, context.terminal.workspace_id, context.terminal.pane_id]
    assert_equal directory_task.id, Hiiro::CurrentTask.new(herdr: client, cwd: @dir, env: {}, pin: false).resolve.id
    flagged_env = { 'HERDR_ENV' => '1' }
    flagged = Hiiro::CurrentTask.new(herdr: client, cwd: @dir, env: flagged_env, pin: false)
    flagged_env.clear
    assert_raises(Hiiro::Error) { flagged.resolve }
    assert_equal directory_task.id, Hiiro::CurrentTask.new(task: directory_task, herdr: client, cwd: @dir, env: { 'HERDR_ENV' => '1' }).resolve.id
    conflict = env.merge('HERDR_WORKSPACE_ID' => 'another')
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(herdr: client, cwd: @dir, env: conflict).resolve }
    explicit = Hiiro::CurrentTask.new(task: directory_task, herdr: client, cwd: @dir, env: conflict).context
    assert_equal directory_task.id, explicit.task.id
    assert_raises(Hiiro::Error) { explicit.terminal.validate!(client) }
    assert_raises(Hiiro::Error) { Hiiro::CurrentTask.new(herdr: client, cwd: @dir, env: { 'HERDR_PANE_ID' => 'stale' }).resolve }
  end

  def test_nested_todo_writes_use_the_inherited_task_even_in_another_tasks_directory
    Hiiro::TaskRecord.db.transaction(rollback: :always) do
      first_dir = File.join(@dir, 'alpha')
      second_dir = File.join(@dir, 'beta')
      FileUtils.mkdir_p([first_dir, second_dir])
      first = Hiiro::TaskRecord.create(name: 'alpha', primary_directory: first_dir)
      Hiiro::TaskRecord.create(name: 'beta', primary_directory: second_dir)
      context = Hiiro::CurrentTask.new(task: first, cwd: second_dir, env: {}).context
      parent = Hiiro.new('t', cwd: second_dir, context: context).extend(Hiiro::TaskCli::Commands)
      [['.', 'context retained'], ['--model', 'beta']].each do |payload|
        child = parent.make_child(:todo, ['add', *payload], builtin_commands: false, external_commands: false) do
          extend Hiiro::TaskCli::Commands
          todo_commands
        end
        status = nil
        output = capture_io do
          begin
            child.run
          rescue SystemExit => error
            status = error.status
          end
        end
        assert_equal 0, status, output.join
      end
      assert_equal ['context retained', '--model beta'], Hiiro::TodoItem.where(task_name: 'alpha').order(:id).select_map(:text)
      assert_equal [], Hiiro::TodoItem.where(task_name: 'beta').select_map(:text)
    end
  end
end
