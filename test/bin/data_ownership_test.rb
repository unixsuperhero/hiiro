require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'time'

class DataOwnershipCommandTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  NOW = '2026-10-12T12:00:00Z'

  PRELOAD = <<~'RUBY'
    require 'hiiro'
    fixed_time = Time.iso8601(ENV.fetch('OWNERSHIP_NOW'))
    Time.define_singleton_method(:now) { fixed_time }
    executor = Hiiro::Effects::NullExecutor.new
    herdr = Hiiro::Herdr.new(executor: executor)
    Hiiro.define_method(:herdr_client) { herdr }
    Hiiro::Notification.define_singleton_method(:show) do |hiiro|
      File.open(ENV.fetch('OWNERSHIP_NOTIFICATIONS'), 'a') do |file|
        file.puts JSON.generate(hiiro.args)
      end
    end
  RUBY

  def setup
    @root = Dir.mktmpdir('hiiro-data-ownership-')
    @home = File.join(@root, 'home')
    @cwd = File.join(@root, 'outside')
    @config = File.join(@home, '.config/hiiro')
    FileUtils.mkdir_p([@cwd, @config])
    @db_path = File.join(@root, 'data.sqlite3')
    @preload = File.join(@root, 'preload.rb')
    @notifications = File.join(@root, 'notifications.jsonl')
    File.write(@preload, PRELOAD)
    @definitions = {
      'services.yml' => "# preserve services\nweb:\n  command: echo web\n",
      'tools.yml' => "# preserve tools\neditor: vim\n",
      'sparse_groups.yml' => "# preserve sparse definitions\nweb:\n  - apps/web\n",
      'config.yml' => "# preserve preferences\neditor: vim\n",
      'tables.yml' => "# preserve table definitions\nresources:\n  type: registry\n",
      'prompt.txt' => "Ordinary prompt bytes.\n"
    }
    @definitions.each { |name, bytes| File.binwrite(File.join(@config, name), bytes) }
    stdout, stderr, status = ruby('-e', 'Hiiro::DB.setup!')
    assert status.success?, "DB bootstrap failed: #{stdout}#{stderr}"
    @db = Sequel.sqlite(@db_path)
    @db[:tasks].insert(id: 42, name: 'prez', session: 'prez', status: 'active')
    @db[:tasks].insert(id: 43, name: 'other', session: 'other', status: 'active')
  end

  def teardown
    @db&.disconnect
    FileUtils.remove_entry(@root) if @root && File.exist?(@root)
  end

  def test_t_tt_and_h_todo_preserve_ids_and_other_writers
    command('t', 'todo', 'add', 'prez', 'Draft slides')
    assert_equal [[1, 'prez', 'Draft slides', 'not_started']], todo_rows
    assert_equal "Added: 2 [ ] Keep unrelated  [research]\n",
      command('h-todo', 'add', 'Keep unrelated', '--tags', 'research')
    command('tt', 'add', 'prez', 'Check references')
    assert_equal "Updated: 1 [>] Draft revised  (prez)\n",
      command('h-todo', 'change', '1', '--text', 'Draft revised', '--status', 'started')
    assert_equal "Draft revised\n", command('tt', 'show', 'prez', '1')
    command('t', 'todo', 'rm', 'prez', '3')
    command('tt', 'add', 'prez', 'Publish slides')
    assert_equal [
      [1, 'prez', 'Draft revised', 'started'],
      [2, nil, 'Keep unrelated', 'not_started'],
      [4, 'prez', 'Publish slides', 'not_started']
    ], todo_rows
    assert_equal "Todo 1 [started]: Draft revised\nTodo 4 [not_started]: Publish slides\n", command('t', 'todo', 'ls', 'prez')
    assert_equal "Draft revised\nPublish slides\n", command('tt', 'ls', 'prez', '--plain')
    assert_equal "1 [>] Draft revised  (prez)\n2 [ ] Keep unrelated  [research]\n4 [ ] Publish slides  (prez)\n",
      command('h-todo', 'ls', '--all')
    assert_equal 'research', @db[:todos].where(id: 2).get(:tags)
    assert_definitions_unchanged
    refute File.exist?(File.join(@config, 'todo.yml'))
  end

  def test_task_and_orphan_scopes_reject_lookalike_ids_without_losing_child_encodings
    @db[:tasks].insert(id: 44, name: 'prez/child', session: 'child', status: 'active')
    @db[:todos].multi_insert([
      { id: 12, task_name: 'prez/child', subtask_name: nil, text: 'Direct child' },
      { id: 112, task_name: 'prez', subtask_name: 'child', text: 'Legacy child' },
      { id: 20, task_name: 'other', text: 'Other task' },
      { id: 21, text: 'Orphan' },
      { id: 22, task_name: 'prez', text: 'Parent task' }
    ])
    assert_equal "Direct child\nLegacy child\n", command('tt', 'ls', 'prez/child', '--plain')
    assert_equal "Todo 21 [not_started]: Orphan\n", command('t', 'todo', 'ls', '-')
    before = todo_rows
    %w[1 20 112x].each do |id|
      stdout, stderr, status = ruby(File.join(ROOT, 'exe/t'), 'todo', 'rm', 'prez/child', id)
      refute status.success?, "Invalid ID #{id} succeeded: #{stdout}#{stderr}"
      assert_equal before, todo_rows
    end
    command('t', 'todo', 'rm', 'prez/child', '12')
    assert_equal "Legacy child\n", command('tt', 'ls', 'prez/child', '--plain')
    command('tt', 'rm', 'prez/child', '112')
    command('tt', 'add', '-', 'New orphan')
    assert_equal [
      [20, 'other', 'Other task', 'not_started'], [21, nil, 'Orphan', 'not_started'],
      [22, 'prez', 'Parent task', 'not_started'], [113, nil, 'New orphan', 'not_started']
    ], todo_rows
    assert_definitions_unchanged
  end

  def test_cli_pin_strings_do_not_become_typed_current_task_state
    assert_equal "prez\n", command('t', 'use', 'prez')
    { 'number_text' => '42', 'bool_text' => 'false', 'object_text' => '{"x":1}', 'array_text' => '[1,2]' }.each do |name, value|
      command('h-link', 'pin', 'set', name, value)
    end
    assert_equal 42, JSON.parse(@db[:pins].where(command: 't', key: 'current_task').get(:value_json))
    assert_equal({
      'array_text' => '[1,2]', 'bool_text' => 'false', 'number_text' => '42', 'object_text' => '{"x":1}'
    }, @db[:pins].where(command: 'h-link').order(:key).to_h { |row| [row[:key], JSON.parse(row[:value_json])] })
    assert_equal "42\n", command('h-link', 'pin', 'get', 'number_text')
    assert_equal "prez\n", command('t', 'current')
    command('h-link', 'pin', 'rm', 'bool_text')
    assert_equal "42\n", command('h-link', 'pin', 'get', 'number_text')
    assert_equal "other\n", command('t', 'use', 'other')
    assert_equal 43, JSON.parse(@db[:pins].where(command: 't', key: 'current_task').get(:value_json))
    assert_equal '[1,2]', JSON.parse(@db[:pins].where(command: 'h-link', key: 'array_text').get(:value_json))
    assert_definitions_unchanged
    refute Dir.exist?(File.join(@config, 'pins'))
  end

  def test_link_edit_keeps_identity_tags_and_unrelated_links
    assert_equal "Saved link #1: https://example.test/slides\n",
      command('h-link', 'add', 'https://example.test/slides', 'Old description', '--shorthand', 'slides', '--tag', 'research')
    command('h-link', 'add', 'https://example.test/other', 'Unrelated', '--shorthand', 'other', '--tag', 'keep')
    editor = File.join(@root, 'editor')
    File.write(editor, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'yaml'
      path = ARGV.fetch(0)
      rows = YAML.safe_load_file(path)
      rows.fetch(0)['url'] = 'https://example.test/revised'
      rows.fetch(0)['description'] = 'Revised description'
      File.write(path, YAML.dump(rows))
    RUBY
    FileUtils.chmod(0o700, editor)
    assert_equal "Updated link #1\n", command('h-link', 'edit', 'slides', env: { 'EDITOR' => editor })
    assert_equal [
      [1, 'https://example.test/revised', 'Revised description', 'slides'],
      [2, 'https://example.test/other', 'Unrelated', 'other']
    ], @db[:links].order(:id).select_map([:id, :url, :description, :shorthand])
    assert_equal [['keep', 'Link', '2'], ['research', 'Link', '1']],
      @db[:tags].order(:name).select_map([:name, :taggable_type, :taggable_id])
    output = command('h-link', 'ls').gsub(/\e\[[\d;]*m/, '')
    assert_equal "1. [slides] https://example.test/revised - Revised description research\n2. [other] https://example.test/other - Unrelated keep\n", output
    assert_definitions_unchanged
    refute File.exist?(File.join(@config, 'links.yml'))
  end

  def test_reminder_pause_resume_once_and_recurrence_survive_processes
    assert_equal "Saved recurring reminder #1: Stretch (every 30m)\n",
      command('h-remind', 'every', 'Stretch', '30m', 'Basso')
    command('h-remind', 'once', 'Submit', '202610121159', 'Glass')
    assert_equal "Paused reminder: Stretch\n", command('h-remind', 'pause', '1')
    assert_equal "  1. [OFF] [30m] Stretch (Basso)\n  2. [ON] [ONCE @ 2026-10-12 11:59] Submit (Glass)\n", command('h-remind', 'ls')
    assert_equal "Triggered (one-time): Submit\nChecked 0 enabled reminders, triggered 1\n1 completed one-time reminder(s) (use 'h remind clean' to remove)\n",
      command('h-remind', 'check', '-v')
    assert_equal [[1, false, false, nil], [2, false, true, NOW]], reminder_state
    assert_equal "Resumed reminder: Stretch\n", command('h-remind', 'resume', '1')
    assert_equal "Triggered: Stretch\nChecked 1 enabled reminders, triggered 1\n1 completed one-time reminder(s) (use 'h remind clean' to remove)\n",
      command('h-remind', 'check', '-v')
    assert_equal [[1, true, false, NOW], [2, false, true, NOW]], reminder_state
    assert_equal "Checked 1 enabled reminders, triggered 0\n1 completed one-time reminder(s) (use 'h remind clean' to remove)\n",
      command('h-remind', 'check', '-v', now: '2026-10-12T12:29:59Z')
    command('h-remind', 'check', '-v', now: '2026-10-12T12:30:00Z')
    assert_equal [[1, true, false, '2026-10-12T12:30:00Z'], [2, false, true, NOW]], reminder_state
    assert_equal [['-m', 'Submit', '-t', 'Reminder', '-s', 'Glass'], ['-m', 'Stretch', '-t', 'Reminder', '-s', 'Basso'], ['-m', 'Stretch', '-t', 'Reminder', '-s', 'Basso']],
      File.readlines(@notifications).map { |line| JSON.parse(line) }
    assert_equal [['Stretch', '30m', 'Basso'], ['Submit', nil, 'Glass']],
      @db[:reminders].order(:id).select_map([:message, :interval, :sound])
    assert_equal "Removed 1 completed one-time reminder(s)\n", command('h-remind', 'clean')
    assert_equal [[1, true, false, '2026-10-12T12:30:00Z']], reminder_state
    assert_definitions_unchanged
    refute File.exist?(File.join(@config, 'reminders.yml'))
  end

  private

  def todo_rows
    @db[:todos].order(:id).select_map([:id, :task_name, :text, :status])
  end

  def reminder_state
    @db[:reminders].order(:id).select_map([:id, :enabled, :once, :last_triggered])
  end

  def assert_definitions_unchanged
    assert_equal @definitions, @definitions.keys.to_h { |name| [name, File.binread(File.join(@config, name))] }
  end

  def ruby(*args, env: {}, now: NOW)
    child_env = ENV.keys.grep(/\A(?:HERDR_|HIIRO_)/).to_h { |key| [key, nil] }
    child_env.merge!(
      'HOME' => @home, 'TZ' => 'UTC', 'HIIRO_TEST_DB' => "sqlite://#{@db_path}",
      'XDG_CONFIG_HOME' => File.join(@home, '.config'), 'XDG_DATA_HOME' => File.join(@home, '.local/share'),
      'OWNERSHIP_REPO' => ROOT, 'OWNERSHIP_NOW' => now, 'OWNERSHIP_NOTIFICATIONS' => @notifications
    )
    Open3.capture3(child_env.merge(env), RbConfig.ruby, '-I', LIB, '-r', @preload, *args, chdir: @cwd)
  end

  def command(bin, *args, **options)
    path = File.join(ROOT, %w[t tt].include?(bin) ? 'exe' : 'bin', bin)
    stdout, stderr, status = ruby(path, *args, **options)
    puts "#{bin} #{args.inspect}: #{stdout.inspect}" if ENV['DATA_OWNERSHIP_TRACE'] == '1'
    assert status.success?, "#{bin} #{args.join(' ')} failed (#{status.exitstatus}):\n#{stdout}#{stderr}"
    stdout
  end
end
