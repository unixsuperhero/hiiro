require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'socket'
require 'timeout'

class TaskCommandTest < Minitest::Test
  BIN = File.expand_path('../../bin/t', __dir__)
  TT_BIN = File.expand_path('../../bin/tt', __dir__)
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
    [Hiiro::TaskRecord, Hiiro::TaskResource, Hiiro::PinRecord, Hiiro::TodoItem].each { |model| model.create_table!(@db) }
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

  def test_task_precedes_leaf_options_and_payload_is_used_once
    directory = File.join(@root, 'slides')
    FileUtils.mkdir_p(directory)
    output = command('directory', 'add', 'prez', '--label', 'Slides', '--primary', directory)
    assert_includes output, "directory\tSlides\t#{File.realpath(directory)}"
    assert_equal File.realpath(directory), @db[:tasks].where(name: 'prez').get(:primary_directory)
    assert_equal [{ task_id: 1, kind: 'directory', target: File.realpath(directory), label: 'Slides' }],
      @db[:task_resources].select(:task_id, :kind, :target, :label).all

    command('next', 'prez', 'Finish', 'slides')
    assert_equal "Finish slides\n", command('next', 'prez')
    command('next', 'prez', '--clear')
    assert_nil @db[:tasks].where(name: 'prez').get(:next_action)
  end

  def test_unknown_forced_task_fails_and_unknown_positional_word_becomes_payload
    command('use', 'prez')
    command('next', 'prez', 'Keep this action')
    assert_includes failure('next', '-t', 'missing', 'Replace action'), 'missing'
    assert_equal "Keep this action\n", command('next', '.')
    command('next', 'Finish', 'slides')
    assert_equal "Finish slides\n", command('next')
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value
  end

  def test_current_persists_across_processes_and_nested_reads_do_not_replace_it
    assert_equal "prez\n", command('use', 'prez')
    assert_equal [], mutations
    assert_equal '1', saved_value
    command('next', 'prez', 'Finish slides')
    command('link', 'add', 'prez', 'https://example.com/slides', '--label', 'Slides')
    command('doc', 'new', 'prez', 'investigation', 'Presentation research')

    assert_equal "prez\n", command('current')
    assert_equal "Finish slides\n", command('next', '.')
    assert_includes command('link', 'list', '.'), "general\tSlides\thttps://example.com/slides"
    assert_equal "#{@home}/notes/work/prez/task-1-investigation.md\n", command('doc', 'list', '.')
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
    command('use', 'other')
    context = { 'HERDR_WORKSPACE_ID' => 'w1' }

    assert_equal "prez\n", command('current', cwd: other_home, env: context)
    assert_equal "other\n", command('use', 'other', cwd: other_home, env: context)
    assert_equal "other\n", command('current')
    assert_equal '2', saved_value
  end

  def test_task_home_code_and_registered_directory_are_context_before_saved
    command('use', 'other')
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
    command('use', 'prez')

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
    command('use', 'prez')

    error = failure('current', cwd: home, env: { 'HERDR_WORKSPACE_ID' => 'w1' })
    assert_match(/ambiguous|shared/i, error)
    assert_includes error, 'prez'
    assert_includes error, 'other'
    assert_equal '1', saved_value
  end

  def test_stale_and_conflicting_herdr_context_never_falls_back_or_switches
    live_workspace('w1', 'prez')
    live_pane('w2:p1', 'w2', 'editor')
    command('use', 'other')
    contexts = [
      { 'HERDR_WORKSPACE_ID' => 'missing' },
      { 'HERDR_PANE_ID' => 'missing' },
      { 'HERDR_WORKSPACE_ID' => 'w1', 'HERDR_PANE_ID' => 'w2:p1' },
    ]
    contexts.each do |context|
      assert_match(/Herdr|workspace|pane/i, failure('workspace', '.', env: context))
      assert_equal [], mutations
      assert_equal '2', saved_value
    end
    assert_equal "other\n", command('current')
  end

  def test_pane_only_context_resolves_its_workspace
    live_workspace('w1', 'prez')
    live_pane('w1:p1', 'w1', 'editor')
    command('use', 'other')
    assert_equal "prez\n", command('current', env: { 'HERDR_PANE_ID' => 'w1:p1' })
    assert_equal "other\n", command('current')
  end

  def test_stale_saved_task_errors_only_when_fallback_is_needed
    command('use', 'prez')
    @db[:tasks].where(name: 'prez').delete
    error = failure('current')
    assert_match(/saved|current|not found|exist/i, error)
    assert_includes command('show', 'other'), 'other [active]'
    assert_equal '1', saved_value
    assert_equal "other\n", command('use', 'other')
    assert_equal "other\n", command('current')
  end

  def test_wor_focuses_existing_workspace_and_saves_only_successful_explicit_switch
    live_workspace('w1', 'prez')
    live_workspace('w2', 'other')
    command('use', 'other')

    assert_includes command('wor', 'prez'), 'w1 prez'
    assert_equal [['herdr', 'workspace', 'focus', 'w1']], mutations
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value

    @stubs['workspace focus w2'] = false
    assert_match(/failed/i, failure('switch', 'other'))
    assert_equal "prez\n", command('current')
    assert_equal '1', saved_value
  end

  def test_workspace_creation_saves_after_success_and_preserves_saved_on_failure
    command('use', 'other')
    @stubs['workspace create'] = JSON.generate('result' => {
      'workspace' => workspace_row('w3', 'prez'),
    })
    assert_includes command('switch', 'prez'), 'w3 prez'
    assert_equal [['herdr', 'workspace', 'create', '--label', 'prez', '--cwd',
      File.realpath(File.join(@home, 'notes/work/prez')), '--focus']], mutations
    assert_equal '1', saved_value

    @stubs['workspace create'] = JSON.generate('result' => {})
    assert_match(/create|failed/i, failure('workspace', 'other'))
    assert_equal "prez\n", command('current')
  end

  def test_workspace_show_and_implicit_open_do_not_save_selection
    live_workspace('w1', 'prez')
    command('use', 'other')
    assert_includes command('workspace', 'prez', '--show'), 'w1 prez'
    assert_equal [], mutations
    assert_equal '2', saved_value

    assert_includes command('workspace', '.', env: { 'HERDR_WORKSPACE_ID' => 'w1' }), 'w1 prez'
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
    command('waiting', 'prez', '--clear')
    assert_equal "active\n", command('status', 'prez')
    assert_equal "prez\tdone\n", command('done', 'prez')
    assert_equal "other  active\nprez   done\n", command
    assert_equal "prez\tarchived\n", command('archive', 'prez')
    assert_equal "other  active\nprez   archived\n", command
    assert_equal "prez\tactive\n", command('status', 'prez', 'active')
    assert_equal "other  active\nprez   active\n", command
  end

  def test_unmatched_workspace_uses_directory_then_saved_task
    live_workspace('w1', 'unrelated')
    command('use', 'other')
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
    command('use', 'other')
    assert_match(/multiple|ambiguous/i, failure('workspace', 'prez'))
    assert_equal [], mutations
    assert_equal "other\n", command('current')
  end

  def test_add_persists_multiple_items_and_resolves_exact_before_unique_prefix
    @db[:tasks].insert(name: 'prez-extra', session: 'prez-extra', status: 'active')
    @db[:tasks].where(name: 'prez').update(next_action: 'Keep the next action', status: 'waiting')
    command('use', 'other')

    command('todo', 'add', 'prez', 'Draft', 'slides', env: { 'HERDR_WORKSPACE_ID' => 'missing' })
    command('todo', 'add', 'prez', 'Check references')
    command('todo', 'add', 'prez-e', 'Prepare appendix')

    expected = [
      ['prez', nil, 'not_started', 'Draft slides'],
      ['prez', nil, 'not_started', 'Check references'],
      ['prez-extra', nil, 'not_started', 'Prepare appendix'],
    ]
    assert_equal expected, @db[:todos].order(:id).select_map([:task_name, :subtask_name, :status, :text])
    assert_equal ['waiting', 'Keep the next action'],
      @db[:tasks].where(name: 'prez').select_map([:status, :next_action]).first
    assert_equal '2', saved_value
    assert_equal [], mutations

    rows = @db[:todos].order(:id).all
    command('done', 'prez')
    command('archive', 'prez')
    assert_equal 'archived', @db[:tasks].where(name: 'prez').get(:status)
    assert_equal rows, @db[:todos].order(:id).all
    assert_includes command('show', 'prez'), 'Draft slides'
  end

  def test_add_with_unknown_forced_task_fails_and_unknown_first_word_is_text
    command('use', 'other')
    assert_match(/not found/i, failure('todo', 'add', '-t', 'Prez', 'Plan', 'the talk'))
    assert_equal %w[other prez], @db[:tasks].order(:name).select_map(:name)
    command('todo', 'add', 'Prez', 'Plan', 'the talk')
    assert_equal [['other', nil, 'Prez Plan the talk', 'not_started']],
      @db[:todos].select_map([:task_name, :subtask_name, :text, :status])
    refute Dir.exist?(File.join(@home, 'notes/work/Prez'))
    assert_equal "other\n", command('current')
    assert_equal '2', saved_value
    assert_equal [], mutations
  end

  def test_add_rejects_ambiguous_or_missing_text_without_changing_task_data_or_files
    @db[:tasks].insert(name: 'prez-extra', session: 'prez-extra', status: 'active')
    command('use', 'other')
    command('todo', 'add', 'other', 'Keep this item')
    before = task_data_and_files

    error = failure('todo', 'add', 'pre', 'Do not create this')
    assert_match(/ambiguous/i, error)
    assert_includes error, 'prez'
    assert_includes error, 'prez-extra'
    assert_equal before, task_data_and_files

    [['missing'], ['missing', ''], ['missing', " \t "], ['prez', ' ']].each do |reference, *words|
      failure(reference, 'todo', 'add', *words)
      assert_equal before, task_data_and_files
    end
    assert_equal [['other', 'Keep this item']], @db[:todos].select_map([:task_name, :text])
  end

  def test_add_preserves_flag_like_text_and_only_leading_help_is_help
    command('todo', 'add', 'prez', 'Literal', '-h', '--help', '--clear', '--', '--unknown=value', 'two words')
    assert_equal [['prez', 'Literal -h --help --clear -- --unknown=value two words']],
      @db[:todos].select_map([:task_name, :text])
    command('todo', 'add', 'prez', '--clear', '--', '--unknown=value', 'two words')
    assert_equal '--clear -- --unknown=value two words', @db[:todos].order(:id).last[:text]
    before = task_data_and_files

    %w[-h --help].each do |flag|
      assert_match(/help|usage|options/i, command('todo', 'add', 'prez', flag, 'Not an item'))
      assert_equal before, task_data_and_files
    end
  end

  def test_rm_deletes_only_exact_ids_associated_with_the_resolved_task
    @db[:tasks].insert(name: 'prez-extra', session: 'prez-extra', status: 'active')
    @db[:tasks].insert(name: 'prez/slides', session: 'slides', status: 'active')
    @db[:todos].multi_insert([
      { id: 12, task_name: 'prez', subtask_name: nil, text: 'Remove exact task item' },
      { id: 112, task_name: 'prez', subtask_name: nil, text: 'Keep suffix lookalike' },
      { id: 20, task_name: 'other', subtask_name: nil, text: 'Keep other task item' },
      { id: 21, task_name: nil, subtask_name: nil, text: 'Keep orphan' },
      { id: 22, task_name: 'prez', subtask_name: 'slides', text: 'Remove legacy split item' },
      { id: 23, task_name: 'prez', subtask_name: 'notes', text: 'Keep sibling subtask' },
      { id: 24, task_name: 'prez-extra', subtask_name: nil, text: 'Remove via unique prefix' },
    ])
    command('use', 'other')
    before = @db[:todos].order(:id).all
    %w[1 2 20 21 22 23].each do |id|
      failure('todo', 'rm', 'prez', id)
      assert_equal before, @db[:todos].order(:id).all
    end

    command('todo', 'rm', 'prez', '12')
    command('todo', 'rm', 'prez-e', '24')
    command('todo', 'rm', 'prez/slides', '22')
    assert_equal [
      [20, 'other', nil, 'Keep other task item'],
      [21, nil, nil, 'Keep orphan'],
      [23, 'prez', 'notes', 'Keep sibling subtask'],
      [112, 'prez', nil, 'Keep suffix lookalike'],
    ], @db[:todos].order(:id).select_map([:id, :task_name, :subtask_name, :text])
    assert_equal '2', saved_value
  end

  def test_rm_rejects_unknown_tasks_and_invalid_arguments_without_creating_or_deleting
    @db[:tasks].insert(name: 'prez-extra', session: 'prez-extra', status: 'active')
    command('todo', 'add', 'prez', 'Keep this item')
    id = @db[:todos].get(:id).to_s
    before = task_data_and_files
    [
      ['prez'], ['missing', id], ['pre', id], ['prez', "#{id}x"],
      ['prez', "#{id}.0"], ['prez', "-#{id}"], ['prez', ''],
      ['prez', id, 'extra'],
    ].each do |reference, *args|
      failure(reference, 'todo', 'rm', *args)
      assert_equal before, task_data_and_files
    end
    assert_equal [['prez', 'Keep this item']], @db[:todos].select_map([:task_name, :text])
  end

  def test_show_includes_all_statuses_in_id_order_and_matches_legacy_full_task_names
    @db[:tasks].insert(name: 'prez/slides', session: 'slides', status: 'active')
    @db[:todos].multi_insert([
      { id: 40, task_name: 'prez', subtask_name: 'slides', status: 'skip', text: 'Skipped legacy item' },
      { id: 10, task_name: 'prez/slides', subtask_name: nil, status: 'not_started', text: 'Direct item' },
      { id: 30, task_name: 'prez/slides', subtask_name: nil, status: 'done', text: 'Completed item' },
      { id: 20, task_name: 'prez', subtask_name: 'slides', status: 'started', text: 'Started legacy item' },
      { id: 50, task_name: 'prez', subtask_name: nil, status: 'not_started', text: 'Parent item' },
      { id: 60, task_name: 'prez/slides', subtask_name: 'notes', status: 'not_started', text: 'Nested item' },
      { id: 70, task_name: nil, subtask_name: nil, status: 'not_started', text: 'Orphan item' },
    ])
    command('use', 'prez/slides')
    before = @db[:todos].order(:id).all
    expected = [
      "Todo 10 [not_started]: Direct item\n",
      "Todo 20 [started]: Started legacy item\n",
      "Todo 30 [done]: Completed item\n",
      "Todo 40 [skip]: Skipped legacy item\n",
    ]
    assert_equal expected, command('show', '.').lines.grep(/\ATodo /)
    assert_equal expected, command('show', 'prez/slides').lines.grep(/\ATodo /)
    assert_equal ["Todo 50 [not_started]: Parent item\n"], command('show', 'prez').lines.grep(/\ATodo /)
    assert_equal before, @db[:todos].order(:id).all
  end

  def test_task_names_that_look_like_commands_are_reachable_with_the_task_option
    names = %w[new show helpful he edit pry add rm lister]
    names.each { |name| @db[:tasks].insert(name: name, session: name, status: 'active') }
    names.each do |name|
      assert_includes command('show', '-t', name), "#{name} [active]"
      command('next', '-t', name, "Work on #{name}")
      assert_equal "Work on #{name}\n", command('next', '-t', name)
    end
    assert_match(/ambiguous/i, failure('show', 'h'))
    assert_includes command('show', 'helpf'), 'helpful [active]'
    assert_includes command('list'), 'lister   active'
    assert_includes command('ls'), 'lister   active'
  end

  def test_root_help_is_exact_and_does_not_resolve_context_or_select_a_task
    @db[:tasks].insert(name: 'help', session: 'help', status: 'active', next_action: 'Do not show this task')
    command('use', 'other')
    before = task_data_and_files
    output = invoke('help', env: { 'HERDR_WORKSPACE_ID' => 'missing' }).first
    assert_includes output, 'todo'
    refute_includes output, 'help [active]'
    refute_includes output, 'Do not show this task'
    assert_equal before, task_data_and_files
    assert_equal [], mutations
  end

  def test_task_and_nested_todo_help_do_not_create_tasks_or_items
    command('todo', 'add', 'prez', 'Keep this item')
    before = task_data_and_files
    [
      ['help'], ['todo', 'help'],
      ['todo', 'add', '--help'], ['todo', 'add', 'prez', '--help'], ['todo', 'rm', '-h'],
      ['todo', 'help', 'missing'],
    ].each do |args|
      expected = args.include?('help') ? (args.include?('todo') ? 'add' : 'todo') : '--help'
      assert_includes invoke(*args).first, expected
      assert_equal before, task_data_and_files
    end
    assert_equal [['prez', 'Keep this item']], @db[:todos].select_map([:task_name, :text])
  end

  def test_named_prefixes_resolve_for_commands_but_new_creates_the_exact_name
    @db[:tasks].insert(name: 'prez-extra', session: 'prez-extra', status: 'active')
    assert_equal "prez\n", command('use', 'prez')
    assert_equal "prez-extra\n", command('use', 'prez-e')
    assert_includes command('show', 'prez-e'), 'prez-extra [active]'
    assert_match(/ambiguous/i, failure('use', 'pre'))
    assert_match(/unexpected/i, failure('show', 'PREZ'))
    command('new', 'pre')
    assert_equal %w[other pre prez prez-extra], @db[:tasks].order(:name).select_map(:name)
    assert Dir.exist?(File.join(@home, 'notes/work/pre'))
    assert_includes command('show', 'pre'), 'pre [active]'
    assert_equal "prez-extra\n", command('current')
  end

  def test_unknown_tasks_are_created_only_by_new
    command('use', 'other')
    before = task_data_and_files
    [['show'], ['current'], ['switch'], ['todo'], ['todo', 'rm', '1'], ['next', 'text'], ['use']].each do |args|
      assert_match(/missing|not found|unknown/i, failure(args.first, '-t', 'missing', *args.drop(1)))
      assert_equal before, task_data_and_files
      assert_equal [], mutations
    end
    command('new', 'created')
    assert_equal 'active', @db[:tasks].where(name: 'created').get(:status)
    assert Dir.exist?(File.join(@home, 'notes/work/created'))
    assert_match(/not found/i, failure('todo', 'add', '-t', 'with-todo', 'First item'))
    assert_equal [], @db[:todos].all
    assert_equal '2', saved_value
  end

  def test_bare_root_lists_all_statuses_without_resolving_current_context
    @db[:tasks].where(name: 'prez').update(status: 'done')
    @db[:tasks].where(name: 'other').update(status: 'archived')
    @db[:tasks].insert(name: 'waiting', session: 'waiting', status: 'waiting')
    @db[:tasks].insert(name: 'active', session: 'active', status: 'active')
    @db[:tasks].where(name: 'waiting').update(waiting_on: 'review', next_action: 'Ship it')
    @db[:todos].insert(text: 'a', status: 'not_started', task_name: 'prez')
    @db[:todos].insert(text: 'b', status: 'started', task_name: 'prez')
    @db[:todos].insert(text: 'c', status: 'done', task_name: 'prez')
    @db[:todos].insert(text: 'd', status: 'skip', task_name: 'active')
    @db[:todos].insert(text: 'e', status: 'not_started', task_name: nil)
    expected = <<~OUT
      active    active
      other     archived
      prez (2)  done
      waiting   waiting   next: Ship it  waiting: review
    OUT
    context = { 'HERDR_WORKSPACE_ID' => 'missing' }
    assert_equal expected, command(env: context)
    assert_equal expected, command('ls', env: context)
    assert_equal expected, command('list', env: context)
    failure('ls', 'extra', env: context)
    assert_nil saved_value
    assert_equal [], mutations
  end

  def test_dot_todos_use_current_context_without_saving_and_never_create_dot
    assert_match(/current|task/i, failure('todo', 'add', '.', 'Not yet'))
    assert_equal %w[other prez], @db[:tasks].order(:name).select_map(:name)
    command('use', 'other')
    live_workspace('w1', 'prez')
    command('todo', 'add', '.', 'Workspace item', env: { 'HERDR_WORKSPACE_ID' => 'w1' })
    command('todo', 'add', '.', 'Saved item')
    assert_equal [['prez', nil, 'Workspace item'], ['other', nil, 'Saved item']],
      @db[:todos].order(:id).select_map([:task_name, :subtask_name, :text])
    assert_equal '2', saved_value
    assert_includes command('todo', '.'), 'Saved item'
    refute_includes command('todo', '.'), 'Workspace item'
  end

  def test_orphan_scope_lists_adds_and_removes_only_orphans_without_resolving_context
    command('use', 'prez')
    command('todo', 'add', 'prez', 'Keep task item')
    context = { 'HERDR_WORKSPACE_ID' => 'missing' }
    command('todo', 'add', '-', 'Orphan item', env: context)
    orphan_id = @db[:todos].where(task_name: nil).get(:id)
    assert_equal [[nil, nil, 'Orphan item']],
      @db[:todos].where(id: orphan_id).select_map([:task_name, :subtask_name, :text])
    output = command('todo', '-', env: context)
    assert_includes output, 'Orphan item'
    refute_includes output, 'Keep task item'
    assert_equal output, command('todo', 'ls', '-', env: context)
    assert_equal output, command('todo', 'list', '-', env: context)
    before = task_data_and_files
    task_id = @db[:todos].where(task_name: 'prez').get(:id)
    failure('todo', 'rm', '-', task_id.to_s, env: context)
    failure('todo', 'rm', 'prez', orphan_id.to_s)
    [[], ['show'], ['current'], ['new'], ['switch'], ['omp']].each do |args|
      failure('show', '-', *args, env: context)
      assert_equal before, task_data_and_files
      assert_equal [], mutations
    end
    command('todo', 'rm', '-', orphan_id.to_s, env: context)
    assert_equal [['prez', nil, 'Keep task item']], @db[:todos].select_map([:task_name, :subtask_name, :text])
    assert_equal '1', saved_value
    assert_equal %w[other prez], @db[:tasks].order(:name).select_map(:name)
  end

  def test_tt_preserves_todo_arguments_and_matches_explicit_and_current_scope
    command('use', 'prez')
    command('add', 'prez', 'Literal', '--help', 'two words', bin: TT_BIN)
    assert_equal [['prez', nil, 'Literal --help two words']],
      @db[:todos].select_map([:task_name, :subtask_name, :text])
    expected = command('todo', 'prez')
    assert_includes expected, 'Literal --help two words'
    assert_equal expected, command('prez', bin: TT_BIN)
    assert_equal expected, command(bin: TT_BIN)
    assert_equal expected, command('ls', 'prez', bin: TT_BIN)
    before = task_data_and_files
    help_output = invoke('help', bin: TT_BIN).first
    assert_includes help_output, 'add'
    assert_includes help_output, 'rm'
    assert_equal before, task_data_and_files
    id = @db[:todos].get(:id)
    command('rm', 'prez', id.to_s, bin: TT_BIN)
    assert_equal [], @db[:todos].all
  end

  def test_ai_commands_start_fresh_native_tools_even_when_matching_panes_exist
    live_workspace('w1', 'prez')
    directory = File.join(@root, 'checkout with spaces')
    FileUtils.mkdir_p(directory)
    @db[:tasks].where(name: 'prez').update(primary_directory: directory)
    new_tab
    [['omp', 'omp'], ['codex', 'codex'], ['cdx', 'codex'], ['claude', 'claude'], ['cld', 'claude']].each do |name, tool|
      live_pane("w1:#{name}", 'w1', name, agent: tool)
      assert_includes command(name, 'prez'), 'w1:t2'
      assert_equal [
        ['herdr', 'tab', 'create', '--workspace', 'w1', '--label', tool, '--cwd', File.realpath(directory), '--focus'],
        ['herdr', 'pane', 'run', 'w1:p2', tool],
      ], session_mutations
    end
  end

  def test_ai_forwarding_preserves_flags_empty_arguments_and_nonleading_resume
    live_workspace('w1', 'prez')
    new_tab
    [
      ['omp', ['--help', '--', 'two words'], 'omp --help -- two\\ words'],
      ['codex', ['--model', 'custom', 'resume', 'session id'], 'codex --model custom resume session\\ id'],
      ['claude', ['', 'resume', '--dangerously-skip-permissions'], "claude '' resume --dangerously-skip-permissions"],
      ['omp', ['resume-more'], 'omp resume-more'],
    ].each do |tool, args, expected|
      assert_includes command(tool, 'prez', *args), 'w1:t2'
      assert_equal ['herdr', 'pane', 'run', 'w1:p2', expected], session_mutations.last
    end
  end

  def test_resume_prefixes_with_arguments_always_launch_native_resume_in_a_new_tab
    live_workspace('w1', 'prez')
    new_tab
    [
      ['omp', 'r', 'omp --resume session\\ id --help -- --flag'],
      ['codex', 'res', 'codex resume session\\ id --help -- --flag'],
      ['claude', 'resume', 'claude --resume session\\ id --help -- --flag'],
    ].each do |tool, prefix, expected|
      live_pane("w1:#{tool}", 'w1', 'unrelated label', agent: tool)
      assert_includes command(tool, 'prez', prefix, 'session id', '--help', '--', '--flag'), 'w1:t2'
      assert_equal ['herdr', 'pane', 'run', 'w1:p2', expected], session_mutations.last
    end
  end

  def test_resume_without_running_agent_launches_native_picker_not_a_label_match
    live_workspace('w1', 'prez')
    new_tab
    [['omp', 'omp --resume'], ['codex', 'codex resume'], ['claude', 'claude --resume']].each do |tool, expected|
      live_pane("w1:label-#{tool}", 'w1', tool)
      assert_includes command(tool, 'prez', 're'), 'w1:t2'
      assert_equal ['herdr', 'pane', 'run', 'w1:p2', expected], session_mutations.last
    end
  end

  def test_resume_without_arguments_focuses_unique_matching_agent_in_task_workspace
    live_workspace('w1', 'prez')
    live_workspace('w2', 'other')
    live_pane('w1:running', 'w1', 'review', agent: 'claude')
    live_pane('w1:label', 'w1', 'claude')
    live_pane('w2:running', 'w2', 'review', agent: 'claude')
    Dir.mktmpdir('hiiro-focus-', '/tmp') do |directory|
      socket_path = File.join(directory, 'focus.sock')
      @stubs['status server'] = "running\nsocket: #{socket_path}\n"
      UNIXServer.open(socket_path) do |server|
        request = Thread.new do
          Timeout.timeout(10) do
            socket = server.accept
            begin
              message = JSON.parse(socket.gets)
              socket.puts(JSON.generate('result' => { 'pane' => { 'focused' => true } }))
              message
            ensure
              socket.close
            end
          end
        end
        begin
          assert_includes command('cld', 'prez', 'resume'), 'w1:running'
          assert_equal({ 'id' => 'hiiro:pane:focus', 'method' => 'pane.focus',
            'params' => { 'pane_id' => 'w1:running' } }, request.value)
          assert_equal [], session_mutations
        ensure
          request.kill
          request.join
        end
      end
    end
  end

  def test_resume_ambiguity_and_native_launch_failure_do_not_silently_succeed
    live_workspace('w1', 'prez')
    live_pane('w1:first', 'w1', 'one', agent: 'omp')
    live_pane('w1:second', 'w1', 'two', agent: 'omp')
    error = failure('omp', 'prez', 'r')
    assert_match(/ambiguous|multiple/i, error)
    assert_includes error, 'w1:first'
    assert_includes error, 'w1:second'
    assert_equal [], session_mutations
    @stubs['tab create'] = JSON.generate('result' => {})
    assert_match(/failed|create/i, failure('codex', 'prez'))
    refute session_mutations.any? { |args| args[1..2] == ['pane', 'run'] }
    new_tab
    @stubs['pane run w1:p2'] = false
    stdout, stderr, status = invoke('codex', 'prez')
    refute status.success?
    assert_match(/could not start|failed/i, stdout + stderr)
    refute_includes stdout, 'w1:t2'
    assert_equal ['herdr', 'pane', 'run', 'w1:p2', 'codex'], session_mutations.last
  end

  def test_todo_show_prints_only_text_and_plain_listing_omits_ids
    command('todo', 'add', 'prez', 'First item')
    command('todo', 'add', 'prez', 'Second item')
    command('todo', 'add', 'other', 'Elsewhere')
    first = @db[:todos].where(text: 'First item').get(:id)
    elsewhere = @db[:todos].where(text: 'Elsewhere').get(:id)
    assert_equal "First item\n", command('todo', 'show', 'prez', first.to_s)
    assert_equal "First item\n", command('show', 'prez', first.to_s, bin: TT_BIN)
    assert_equal "First item\nSecond item\n", command('ls', 'prez', '--plain', bin: TT_BIN)
    assert_match(/does not belong/, failure('todo', 'show', 'prez', elsewhere.to_s))
    assert_match(/exact decimal/i, failure('todo', 'show', 'prez', 'abc'))
    failure('todo', 'show', 'prez')
  end

  def test_tree_commands_create_detach_and_resume_worktrees_without_herdr
    seed = File.join(@root, 'seed')
    FileUtils.mkdir_p(seed)
    git = %w[git -c user.email=t@example.com -c user.name=t -c init.defaultBranch=main]
    system(*git, '-C', seed, 'init', '-q', out: File::NULL, err: File::NULL)
    system(*git, '-C', seed, 'commit', '-q', '--allow-empty', '-m', 'init', out: File::NULL, err: File::NULL)
    work = File.join(@home, 'work')
    FileUtils.mkdir_p(work)
    system(*git, 'clone', '-q', '--bare', seed, File.join(work, '.bare'), out: File::NULL, err: File::NULL)
    File.write(File.join(work, '.git'), "gitdir: .bare\n")
    tree = File.join(work, 'demo/main')
    @stubs['status server'] = false

    output = command('tree', 'new', 'demo')
    assert Dir.exist?(tree)
    assert_includes output, 'Created worktree demo/main'
    assert_includes output, 'Herdr is not running'
    assert_equal 'demo/main', @db[:tasks].where(name: 'demo').get(:tree)
    assert_equal "demo/main\t#{tree}\n", command('tree', 'demo')
    assert_equal "#{File.realpath(tree)}\n", command('path', 'demo')
    assert_equal "(detached)\n", command('branch', 'demo')
    assert_equal "demo\n", command('current', cwd: tree)
    assert_match(/already has worktree/, failure('tree', 'new', 'demo'))

    command('tree', 'rm', 'demo')
    assert_nil @db[:tasks].where(name: 'demo').get(:tree)
    assert_equal [['directory', tree]], @db[:task_resources].select_map([:kind, :target])
    assert Dir.exist?(tree)
    assert_match(/no worktree/i, failure('tree', 'demo'))

    command('tree', 'resume', 'demo', 'demo/main')
    assert_equal 'demo/main', @db[:tasks].where(name: 'demo').get(:tree)
    assert_includes command('tree', 'new', 'demo/api'), 'Created worktree demo/api'
    assert Dir.exist?(File.join(work, 'demo/api'))
    assert_equal [], mutations
  end

  private

  def invoke(*args, cwd: @cwd, env: {}, bin: BIN)
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
    Open3.capture3(child_env.merge(env), RbConfig.ruby, '-I', LIB, '-r', @preload, bin, *args, chdir: cwd)
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

  def task_data_and_files
    data = %i[tasks todos pins task_resources].to_h { |table| [table, @db[table].order(:id).all] }
    files = Dir.glob(File.join(@home, '**', '*'), File::FNM_DOTMATCH).sort.to_h do |path|
      [path, File.file?(path) ? File.binread(path) : nil]
    end
    [data, files]
  end

  def saved_value
    @db[:pins].where(command: 't', key: 'current_task').get(:value_json)
  end

  def mutations
    JSON.parse(File.read(@effects_path)).filter_map do |call|
      args = call.fetch('args')
      args if call['method'] == 'run' || (%w[workspace tab].include?(args[1]) && args[2] == 'create')
    end
  end

  def session_mutations
    mutations.select { |args| [%w[tab create], %w[pane run]].include?(args[1..2]) }
  end

  def new_tab
    @stubs['tab create'] = JSON.generate('result' => {
      'tab' => { 'tab_id' => 'w1:t2' },
      'root_pane' => { 'pane_id' => 'w1:p2' },
    })
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

  def live_pane(id, workspace_id, label, agent: nil)
    row = { 'pane_id' => id, 'workspace_id' => workspace_id, 'tab_id' => "#{workspace_id}:t1",
      'label' => label, 'agent' => agent }
    @panes ||= {}
    (@panes[workspace_id] ||= []) << row
    @stubs["pane list --workspace #{workspace_id}"] = JSON.generate('result' => { 'panes' => @panes[workspace_id] })
    @stubs["pane get #{id}"] = JSON.generate('result' => { 'pane' => row })
  end
end
