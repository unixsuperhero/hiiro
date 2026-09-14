require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'

class TaskCommandTest < Minitest::Test
  BIN = File.expand_path('../../bin/t', __dir__)
  LIB = File.expand_path('../../lib', __dir__)

  PRELOAD = <<~'RUBY'
    class Hiiro
      class Config
        def self.plugin_files = []
      end
    end
    require 'hiiro'
    executor = Hiiro::Effects::NullExecutor.new
    JSON.parse(File.read(ENV.fetch('TASK_TEST_STUBS'))).each do |pattern, response|
      executor.stub(pattern, response)
    end
    herdr = Hiiro::Herdr.new(executor: executor)
    Hiiro.define_method(:herdr_client) { herdr }
    at_exit { File.write(ENV.fetch('TASK_TEST_EFFECTS'), JSON.generate(executor.calls)) }
  RUBY

  def setup
    @root = Dir.mktmpdir('hiiro-task-cli-')
    @home = File.join(@root, 'home')
    @cwd = File.join(@root, 'outside')
    FileUtils.mkdir_p([@home, @cwd])
    @db_path = File.join(@root, 'tasks.sqlite3')
    @db = Sequel.sqlite(@db_path)
    [Hiiro::TaskRecord, Hiiro::TaskResource, Hiiro::PinRecord].each { |model| model.create_table!(@db) }
    Hiiro::TaskRecord.migrate!(@db)
    @db[:tasks].insert(id: 1, name: 'prez', session: 'prez', status: 'active')
    @db[:tasks].insert(id: 2, name: 'other', session: 'other', status: 'active')
    @preload = File.join(@root, 'preload.rb')
    File.write(@preload, PRELOAD)
    @stubs = {}
  end

  def teardown
    @db&.disconnect
    FileUtils.remove_entry(@root) if @root && File.exist?(@root)
  end

  def test_task_follows_leaf_options_and_payload_is_used_once
    directory = File.join(@root, 'slides')
    FileUtils.mkdir_p(directory)
    output = command('directory', 'add', '--label', 'Slides', '--primary', 'prez', directory)
    assert_includes output, "directory\tSlides\t#{File.realpath(directory)}"
    assert_equal File.realpath(directory), @db[:tasks].where(name: 'prez').get(:primary_directory)
    assert_equal [{ task_id: 1, kind: 'directory', target: File.realpath(directory), label: 'Slides' }],
      @db[:task_resources].select(:task_id, :kind, :target, :label).all

    command('next', 'prez', 'Finish', 'slides')
    assert_equal "Finish slides\n", command('next', 'prez')
    command('next', '--clear', 'prez')
    assert_nil @db[:tasks].where(name: 'prez').get(:next_action)
  end

  def test_unknown_explicit_task_and_missing_task_before_payload_never_use_saved_task
    command('current', 'prez')
    command('next', 'prez', 'Keep this action')
    assert_includes failure('next', 'missing', 'Replace action'), 'missing'
    assert_includes failure('next', 'Finish', 'slides'), 'Finish'
    assert_equal "Keep this action\n", command('next')
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value
  end

  def test_current_persists_across_processes_and_nested_reads_do_not_replace_it
    assert_equal "prez\n", command('current', 'prez')
    assert_equal [], mutations
    assert_equal '1', saved_value
    command('next', 'prez', 'Finish slides')
    command('link', 'add', 'prez', 'https://example.com/slides', '--label', 'Slides')
    command('doc', 'new', 'prez', 'investigation', 'Presentation research')

    assert_equal "prez\n", command('current')
    assert_equal "Finish slides\n", command('next')
    assert_includes command('link', 'list'), "general\tSlides\thttps://example.com/slides"
    assert_equal "#{@home}/notes/work/prez/task-1-investigation.md\n", command('doc', 'list')
    assert_includes command('show', 'other'), 'other [active]'
    command('directory', 'list', 'other')
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value
  end

  def test_workspace_context_takes_priority_over_cwd_and_saved_but_not_explicit_name
    @db[:tasks].where(name: 'prez').update(session: 'prez.slides')
    live_workspace('w1', 'prez_slides')
    other_home = File.join(@home, 'notes/work/other')
    FileUtils.mkdir_p(other_home)
    command('current', 'other')
    context = { 'HERDR_WORKSPACE_ID' => 'w1' }

    assert_equal "prez\n", command('current', cwd: other_home, env: context)
    assert_equal "other\n", command('current', 'other', cwd: other_home, env: context)
    assert_equal "other\n", command('current')
    assert_equal '2', saved_value
  end

  def test_task_home_code_and_registered_directory_are_context_before_saved
    command('current', 'other')
    home = File.join(@home, 'notes/work/prez')
    code = File.join(@root, 'checkout')
    registered = File.join(@root, 'research')
    @db[:tasks].where(name: 'prez').update(primary_directory: code)
    @db[:task_resources].insert(task_id: 1, kind: 'directory', target: registered)

    [home, code, registered].each do |path|
      nested = File.join(path, 'nested')
      FileUtils.mkdir_p(nested)
      assert_equal "prez\n", command('current', cwd: nested)
    end
    sibling = File.join(@root, 'checkout-other')
    FileUtils.mkdir_p(sibling)
    assert_equal "other\n", command('current', cwd: sibling)
    assert_equal "other\n", command('current')
    assert_equal '2', saved_value
  end

  def test_ambiguous_directories_error_instead_of_using_saved_task
    shared = File.join(@root, 'shared')
    FileUtils.mkdir_p(shared)
    @db[:tasks].update(primary_directory: shared)
    command('current', 'prez')

    error = failure('current', cwd: shared)
    assert_match(/ambiguous/i, error)
    assert_includes error, 'prez'
    assert_includes error, 'other'
    assert_equal "prez\n", command('current')
  end

  def test_ambiguous_normalized_workspace_labels_error_before_cwd_fallback
    @db[:tasks].where(name: 'prez').update(session: 'slides.v1')
    @db[:tasks].where(name: 'other').update(session: 'slides_v1')
    live_workspace('w1', 'slides_v1')
    home = File.join(@home, 'notes/work/prez')
    FileUtils.mkdir_p(home)
    command('current', 'prez')

    error = failure('current', cwd: home, env: { 'HERDR_WORKSPACE_ID' => 'w1' })
    assert_match(/ambiguous|shared/i, error)
    assert_includes error, 'prez'
    assert_includes error, 'other'
    assert_equal '1', saved_value
  end

  def test_stale_and_conflicting_herdr_context_never_falls_back_or_switches
    live_workspace('w1', 'prez')
    live_pane('w2:p1', 'w2', 'editor')
    command('current', 'other')
    contexts = [
      { 'HERDR_WORKSPACE_ID' => 'missing' },
      { 'HERDR_PANE_ID' => 'missing' },
      { 'HERDR_WORKSPACE_ID' => 'w1', 'HERDR_PANE_ID' => 'w2:p1' },
    ]
    contexts.each do |context|
      assert_match(/Herdr|workspace|pane/i, failure('workspace', env: context))
      assert_equal [], mutations
      assert_equal '2', saved_value
    end
    assert_equal "other\n", command('current')
  end

  def test_pane_only_context_resolves_its_workspace
    live_workspace('w1', 'prez')
    live_pane('w1:p1', 'w1', 'editor')
    command('current', 'other')
    assert_equal "prez\n", command('current', env: { 'HERDR_PANE_ID' => 'w1:p1' })
    assert_equal "other\n", command('current')
  end

  def test_stale_saved_task_errors_only_when_fallback_is_needed
    command('current', 'prez')
    @db[:tasks].where(name: 'prez').delete
    error = failure('current')
    assert_match(/saved|current|not found|exist/i, error)
    assert_includes command('show', 'other'), 'other [active]'
    assert_equal '1', saved_value
    assert_equal "other\n", command('current', 'other')
    assert_equal "other\n", command('current')
  end

  def test_wor_focuses_existing_workspace_and_saves_only_successful_explicit_switch
    live_workspace('w1', 'prez')
    live_workspace('w2', 'other')
    command('current', 'other')

    assert_includes command('wor', 'prez'), 'w1 prez'
    assert_equal [['herdr', 'workspace', 'focus', 'w1']], mutations
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value

    @stubs['workspace focus w2'] = false
    assert_match(/failed/i, failure('workspace', 'other'))
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value
  end

  def test_workspace_creation_saves_after_success_and_preserves_saved_on_failure
    command('current', 'other')
    @stubs['workspace create'] = JSON.generate('result' => {
      'workspace' => workspace_row('w3', 'prez'),
    })
    assert_includes command('workspace', 'prez'), 'w3 prez'
    assert_equal [['herdr', 'workspace', 'create', '--label', 'prez', '--cwd',
      File.realpath(File.join(@home, 'notes/work/prez')), '--focus']], mutations
    assert_equal '1', saved_value

    @stubs['workspace create'] = JSON.generate('result' => {})
    assert_match(/create|failed/i, failure('workspace', 'other'))
    assert_equal "prez\n", command('current')
  end

  def test_workspace_show_and_implicit_open_do_not_save_selection
    live_workspace('w1', 'prez')
    command('current', 'other')
    assert_includes command('workspace', '--show', 'prez'), 'w1 prez'
    assert_equal [], mutations
    assert_equal '2', saved_value

    assert_includes command('workspace', env: { 'HERDR_WORKSPACE_ID' => 'w1' }), 'w1 prez'
    assert_equal [['herdr', 'workspace', 'focus', 'w1']], mutations
    assert_equal "other\n", command('current')
  end

  def test_pane_run_preserves_command_arguments_after_task_and_pane
    live_workspace('w1', 'prez')
    live_pane('w1:p1', 'w1', 'editor')
    command('pane', 'run', 'prez', 'editor', '--', 'printf', '%s', 'hello world', '--flag')
    assert_equal [['herdr', 'pane', 'run', 'w1:p1', 'printf \\%s hello\\ world --flag']], mutations
  end

  def test_document_and_state_commands_keep_task_and_payload_distinct
    path = File.join(@home, 'notes/work/prez/task-1-investigation.md')
    assert_equal "#{path}\n", command('doc', 'new', 'prez', 'investigation', 'Presentation', 'research')
    assert_equal "# Presentation research\n\n", File.read(path)
    command('waiting', 'prez', 'Design review')
    assert_equal "waiting\n", command('status', 'prez')
    assert_equal "Design review\n", command('waiting', 'prez')
    command('waiting', '--clear', 'prez')
    assert_equal "active\n", command('status', 'prez')
    assert_equal "prez\tdone\n", command('done', 'prez')
    assert_equal "other\tactive\n", command('list')
    assert_equal "prez\tdone\n", command('list', '--all', 'prez')
    assert_equal "prez\tactive\n", command('status', 'prez', 'active')
    assert_equal "other\tactive\nprez\tactive\n", command('list')
  end

  def test_unmatched_workspace_uses_directory_then_saved_task
    live_workspace('w1', 'unrelated')
    command('current', 'other')
    home = File.join(@home, 'notes/work/prez')
    FileUtils.mkdir_p(home)
    context = { 'HERDR_WORKSPACE_ID' => 'w1' }

    assert_equal "prez\n", command('current', cwd: home, env: context)
    assert_equal "other\n", command('current', env: context)
    assert_equal '2', saved_value
  end

  def test_duplicate_live_workspace_labels_do_not_focus_an_arbitrary_workspace
    live_workspace('w1', 'prez')
    live_workspace('w2', 'prez')
    command('current', 'other')
    assert_match(/multiple|ambiguous/i, failure('workspace', 'prez'))
    assert_equal [], mutations
    assert_equal "other\n", command('current')
  end

  private

  def invoke(*args, cwd: @cwd, env: {})
    stubs_path = File.join(@root, 'stubs.json')
    @effects_path = File.join(@root, 'effects.json')
    File.write(stubs_path, JSON.generate(@stubs))
    child_env = ENV.keys.grep(/\A(?:HERDR_|HIIRO_)/).to_h { |key| [key, nil] }
    child_env.merge!(
      'HOME' => @home, 'HIIRO_TEST_DB' => "sqlite://#{@db_path}",
      'XDG_CONFIG_HOME' => File.join(@home, '.config'),
      'XDG_DATA_HOME' => File.join(@home, '.local/share'),
      'TASK_TEST_STUBS' => stubs_path, 'TASK_TEST_EFFECTS' => @effects_path,
    )
    Open3.capture3(child_env.merge(env), RbConfig.ruby, '-I', LIB, '-r', @preload, BIN, *args, chdir: cwd)
  end

  def command(*args, **options)
    stdout, stderr, status = invoke(*args, **options)
    assert status.success?, "t #{args.join(' ')} failed (#{status.exitstatus}):\n#{stdout}#{stderr}"
    stdout
  end

  def failure(*args, **options)
    stdout, stderr, status = invoke(*args, **options)
    refute status.success?, "t #{args.join(' ')} unexpectedly succeeded:\n#{stdout}#{stderr}"
    stdout + stderr
  end

  def saved_value
    @db[:pins].where(command: 't', key: 'current_task').get(:value_json)
  end

  def mutations
    JSON.parse(File.read(@effects_path)).filter_map do |call|
      args = call.fetch('args')
      args if call['method'] == 'run' || args[1..2] == ['workspace', 'create']
    end
  end

  def workspace_row(id, label)
    { 'workspace_id' => id, 'label' => label, 'tab_count' => 1, 'pane_count' => 1 }
  end

  def live_workspace(id, label)
    @workspaces ||= []
    row = workspace_row(id, label)
    @workspaces << row
    @stubs['workspace list'] = JSON.generate('result' => { 'workspaces' => @workspaces })
    @stubs["workspace get #{id}"] = JSON.generate('result' => { 'workspace' => row })
  end

  def live_pane(id, workspace_id, label)
    row = { 'pane_id' => id, 'workspace_id' => workspace_id, 'tab_id' => "#{workspace_id}:t1", 'label' => label }
    @stubs["pane list --workspace #{workspace_id}"] = JSON.generate('result' => { 'panes' => [row] })
    @stubs["pane get #{id}"] = JSON.generate('result' => { 'pane' => row })
  end
end
