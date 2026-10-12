require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'
require 'rbconfig'
require 'timeout'

class DBMigrationTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')

  def setup
    @home = Dir.mktmpdir('hiiro-migration-')
    @base = File.join(@home, '.config/hiiro')
    FileUtils.mkdir_p(@base)
    @env = {'HOME' => @home, 'HIIRO_TEST_DB' => "sqlite://#{@home}/records.sqlite", 'HIIRO_INVOCATION_ID' => nil}
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def source(path, value)
    target = File.join(@base, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, YAML.dump(value))
    target
  end

  def child(code, env: @env, success: true)
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', LIB, '-rhiiro', '-e', "Hiiro::DB.setup!; #{code}", chdir: ROOT)
    assert_equal success, status.success?, "#{out}\n#{err}"
    JSON.parse(out)
  end

  def snapshot
    child("db=Hiiro::DB.connection; puts JSON.generate(todos:db[:todos].order(:id).all, sources:db[:migration_sources].all, rows:db[:migration_rows].all, complete:Hiiro::DB.migrated?)")
  end

  def test_setup_never_imports_and_invalid_selected_import_rolls_back_every_store
    todo = source('todo.yml', {'todos' => [{'id' => 4, 'text' => 'keep'}, {'id' => 5, 'text' => nil}]})
    source('links.yml', [{'url' => 'https://example.test/retained'}])
    before = File.binread(todo)
    assert_equal({'todos' => [], 'sources' => [], 'rows' => [], 'complete' => false}, snapshot)
    result = child("p=Hiiro::DB.migration_plan; begin; Hiiro::DB.migrate!(plan:p); rescue Hiiro::DB::ImportError => e; puts JSON.generate(error:e.message); end")
    assert_equal 'todos/text: null not allowed', result['error']
    assert_equal({'todos' => [], 'sources' => [], 'rows' => [], 'complete' => false}, snapshot)
    assert_equal before, File.binread(todo)
    assert_equal false, File.exist?(todo + '.bak')
  end

  def test_conflicts_and_source_changed_after_plan_leave_original_canonical_values
    source('todo.yml', {'todos' => [{'id' => 7, 'text' => 'legacy'}]})
    result = child("Hiiro::DB.connection[:todos].insert(id:7,text:'canonical'); p=Hiiro::DB.migration_plan; puts JSON.generate(errors:p[:errors],text:Hiiro::TodoItem[7].text,complete:Hiiro::DB.migrated?)")
    assert_equal ['Canonical conflict: todos/7 fields text'], result['errors']
    assert_equal 'canonical', result['text']
    assert_equal false, result['complete']
    source('todo.yml', {'todos' => [{'id' => 8, 'text' => 'planned'}]})
    result = child("p=Hiiro::DB.migration_plan; File.write(Hiiro::Config.path('todo.yml'), 'changed'); begin; Hiiro::DB.migrate!(plan:p); rescue Hiiro::DB::ImportError => e; puts JSON.generate(error:e.message,ids:Hiiro::TodoItem.select_map(:id)); end")
    assert_match(/Source changed after plan:/, result['error'])
    assert_equal [7], result['ids']
  end

  def test_repeat_preserves_later_updates_deletions_and_new_records_and_changed_source_rejects
    todo = source('todo.yml', {'next_id' => 50, 'todos' => [{'id' => 7, 'text' => 'old'}, {'id' => 8, 'text' => 'delete later'}]})
    child("Hiiro::DB.migrate!; puts JSON.generate(Hiiro::TodoItem.order(:id).select_map(:id))")
    result = child("Hiiro::DB.connection[:todos].where(id:7).update(text:'newer'); Hiiro::DB.connection[:todos].where(id:8).delete; id=Hiiro::DB.connection[:todos].insert(text:'concurrent'); report=Hiiro::DB.migrate!; puts JSON.generate(id:id,report:report,todos:Hiiro::TodoItem.order(:id).all.map{|r| [r.id,r.text]})")
    assert_equal 50, result['id']
    assert_equal [[7, 'newer'], [50, 'concurrent']], result['todos']
    assert_equal 'previously-applied', result['report'][0]['status']
    assert_equal 2, result['report'][0]['canonical_changes_or_deletions']
    source('todo.yml', {'todos' => [{'id' => 7, 'text' => 'changed source'}]})
    result = child("p=Hiiro::DB.migration_plan; puts JSON.generate(errors:p[:errors],text:Hiiro::TodoItem[7].text)")
    assert_match(/Changed previously imported source:/, result['errors'][0])
    assert_equal 'newer', result['text']
    assert File.file?(todo)
  end

  def test_extensionless_and_yml_pins_preserve_types_and_explicit_backup_selection
    source('pins/h-link', {'number-string' => '42', 'boolean-string' => 'false', 'json-string' => '{"x":1}', 'number' => 42, 'false' => false, 'array' => [1, '2'], 'null' => nil})
    backup = source('pins/t.yml.bak', {'current_task' => 11})
    source('tasks/tasks.yml', {'tasks' => [{'id' => 11, 'name' => 'alpha'}]})
    result = child("Hiiro::DB.migrate!; puts JSON.generate(Hiiro::PinRecord.for_command('h-link').to_h{|pin| [pin.key,pin.value]})")
    assert_equal({'number-string' => '42', 'boolean-string' => 'false', 'json-string' => '{"x":1}', 'number' => 42, 'false' => false, 'array' => [1, '2'], 'null' => nil}, result)
    result = child("before=Hiiro::PinRecord.find_key('t','current_task'); Hiiro::DB.migrate!(sources:[#{backup.inspect}]); puts JSON.generate(before:before&.value,after:Hiiro::PinRecord.find_key('t','current_task').value)")
    assert_equal({'before' => nil, 'after' => 11}, result)
  end

  def test_pin_source_variant_and_legacy_raw_ambiguity_conflicts_are_truthful
    source('pins/h-link', {'key' => '42'})
    variant = source('pins/h-link.yml', {'key' => 42})
    result = child("puts JSON.generate(Hiiro::DB.migration_plan[:errors])")
    assert_equal ['Conflicting source variants: pins/h-link'], result
    File.delete(variant)
    result = child("Hiiro::DB.connection[:pins].insert(command:'h-link',key:'key',value_json:'42',value_format:'legacy'); Hiiro::DB.migrate!; puts JSON.generate(value:Hiiro::PinRecord.find_key('h-link','key').value,format:Hiiro::PinRecord.find_key('h-link','key').value_format)")
    assert_equal({'value' => '42', 'format' => 'json'}, result)
  end

  def test_duplicate_no_id_reminders_remain_distinct_and_reordering_is_not_new_generation
    row = {'message' => 'same', 'interval' => '1m', 'sound' => 'Glass', 'enabled' => false, 'once' => true, 'trigger_at' => '2030-01-01T00:00:00Z', 'last_triggered' => '2029-12-01T00:00:00Z'}
    source('reminders.yml', [row, row])
    result = child("Hiiro::DB.migrate!; Hiiro::DB.migrate!; puts JSON.generate(Hiiro::Reminder.order(:id).all.map{|r| [r.id,r.message,r.enabled,r.once,r.trigger_at,r.last_triggered]})")
    assert_equal [[1, 'same', false, true, '2030-01-01T00:00:00Z', '2029-12-01T00:00:00Z'], [2, 'same', false, true, '2030-01-01T00:00:00Z', '2029-12-01T00:00:00Z']], result
  end

  def test_task_details_resources_tag_identities_and_qualified_prs_survive
    source('tasks/tasks.yml', {'tasks' => [{'id' => 12, 'name' => 'alpha/sub', 'status' => 'waiting'}]})
    source('tasks/task_alpha_sub.yml', {'session' => 'alpha/sub', 'tree' => '/tmp/work', 'windows' => [{'index' => 2, 'name' => 'docs'}], 'saved_at' => '2020-01-01', 'custom' => false, 'resources' => [{'id' => 40, 'kind' => 'url', 'target' => 'https://example.test', 'label' => 'ref'}]})
    source('tasks/task_standalone.yml', {'name' => 'standalone', 'app' => 'editor', 'windows' => []})
    source('branches.yml', {'branches' => [{'id' => 20, 'name' => 'feature', 'worktree' => '/tmp/work'}]})
    source('links.yml', [{'id' => 22, 'url' => 'https://example.test'}])
    source('pinned_prs.yml', [{'id' => 30, 'repo' => 'one/repo', 'number' => 1, 'title' => 'first'}, {'id' => 31, 'repo' => 'two/repo', 'number' => 1, 'title' => 'second'}])
    source('tags.yml', {'task' => {'alpha/sub' => ['work']}, 'branch' => {'feature' => ['ready']}, 'link' => {'22' => ['doc']}, 'pinned_pr' => {'31' => ['review']}})
    result = child("Hiiro::DB.migrate!; puts JSON.generate(task:Hiiro::TaskRecord[12].values, metadata:Hiiro::TaskRecord[12].metadata, standalone:Hiiro::TaskRecord.find_by_name('standalone').metadata,resources:Hiiro::TaskResource.all.map(&:values),tags:Hiiro::Tag.order(:id).all.map{|t| [t.taggable_type,t.taggable_id,t.name]},prs:Hiiro::PinnedPr.order(:id).all.map{|r| [r.id,r.repo,r.number]})")
    assert_equal 'waiting', result['task']['status']
    assert_equal '/tmp/work', result['task']['tree']
    assert_equal({'windows' => [{'index' => 2, 'name' => 'docs'}], 'saved_at' => '2020-01-01', 'custom' => false}, result['metadata'])
    assert_equal({'windows' => []}, result['standalone'])
    assert_equal 12, result['resources'][0]['task_id']
    assert_equal 40, result['resources'][0]['id']
    assert_equal [['Task', 'alpha/sub', 'work'], ['Branch', 'feature', 'ready'], ['Link', '22', 'doc'], ['PinnedPr', '31', 'review']], result['tags']
    assert_equal [[30, 'one/repo', 1], [31, 'two/repo', 1]], result['prs']
  end

  def test_interrupted_import_rolls_back_rows_ledger_and_completion_and_retry_succeeds
    path = source('todo.yml', {'todos' => [{'id' => 1, 'text' => 'first'}, {'id' => 2, 'text' => 'second'}]})
    original = File.binread(path)
    code = <<~RUBY
      Hiiro::DB.setup!; plan=Hiiro::DB.migration_plan
      class << Hiiro::DB
        alias original_verify_row! verify_row!
        def verify_row!(*args)
          result=original_verify_row!(*args)
          if args[0] == :todos
            puts 'ready'; STDOUT.flush; sleep 60
          end
          result
        end
      end
      Hiiro::DB.migrate!(plan:plan)
    RUBY
    Open3.popen3(@env, RbConfig.ruby, '-I', LIB, '-rhiiro', '-e', code, chdir: ROOT) do |stdin, stdout, stderr, process|
      stdin.close
      assert_equal "ready\n", Timeout.timeout(20) { stdout.gets }, stderr.read_nonblock(4096, exception: false).inspect
      Process.kill('KILL', process.pid)
      process.value
    end
    assert_equal({'todos' => [], 'sources' => [], 'rows' => [], 'complete' => false}, snapshot)
    assert_equal original, File.binread(path)
    result = child("Hiiro::DB.migrate!; puts JSON.generate(ids:Hiiro::TodoItem.order(:id).select_map(:id),complete:Hiiro::DB.migrated?)")
    assert_equal({'ids' => [1, 2], 'complete' => true}, result)
  end

  def test_export_exclusive_create_and_full_recovery_reload_refuses_later_write_conflicts
    excluded = %w[services.yml tools.yml sparse_groups.yml app_files.yml tables.yml config.yml queue/prompt.yml captures/output.txt]
    excluded.each { |path| source(path, {'ordinary' => "#{path}\n"}) }
    bytes = excluded.to_h { |path| [path, File.binread(File.join(@base, path))] }
    source('todo.yml', {'next_id' => 90, 'todos' => [{'id' => 9, 'text' => 'original'}]})
    source('pins/h-link', {'string' => '42', 'integer' => 42, 'boolean' => false, 'null' => nil, 'array' => ['false', 0, true]})
    source('pinned_prs.yml', [{'id' => 11, 'repo' => 'one/repo', 'number' => 5, 'statusCheckRollup' => [{'name' => 'ci', 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS', 'detailsUrl' => 'https://example.test/check'}]}])
    source('reminders.yml', [{'id' => 17, 'message' => 'repeat', 'interval' => '1m', 'enabled' => false, 'once' => false, 'sound' => 'Glass', 'last_triggered' => '2020-01-01T00:00:00Z'}])
    export = File.join(@home, 'export.json')
    result = child("Hiiro::DB.migrate!; task=Hiiro::TaskRecord.create(name:'project'); resource=Hiiro::TaskResource.create(task_id:task.id,kind:'file',target:'/tmp/ref'); entry=Hiiro::RegistryEntry.create(resource_type:'service',name:'build',short_name:'b',task_id:task.id,meta_json:JSON.generate({'x'=>false})); entry.tag('keep'); Hiiro::DB.connection[:captures].insert(id:14,name:'failure',path:'captures/output.txt',command:'false',exit_status:1); Hiiro::DB.export!(#{export.inspect}); puts JSON.generate(task:task.id,resource:resource.id,entry:entry.id)")
    assert_equal({'task' => 1, 'resource' => 1, 'entry' => 1}, result)
    original = File.binread(export)
    result = child("begin; Hiiro::DB.export!(#{export.inspect}); rescue Errno::EEXIST; puts JSON.generate(error:'exists'); end")
    assert_equal({'error' => 'exists'}, result)
    assert_equal original, File.binread(export)
    recovery_env = @env.merge('HIIRO_TEST_DB' => "sqlite://#{@home}/recovered.sqlite")
    child("Hiiro::DB.restore!(#{export.inspect}); Hiiro::DB.export!(#{(export + '.restored').inspect}); puts JSON.generate(text:Hiiro::TodoItem[9].text)", env: recovery_env)
    expected = JSON.parse(original)['payload']
    actual = JSON.parse(File.binread(export + '.restored'))['payload']
    assert_equal expected, actual
    assert_equal [[11, 5, 'ci', 'SUCCESS']], actual['tables']['check_runs'].map { |row| row.values_at('pr_id', 'pr_number', 'name', 'conclusion') }
    assert_equal [[17, 'repeat', false, 'Glass']], actual['tables']['reminders'].map { |row| row.values_at('id', 'message', 'enabled', 'sound') }
    assert_equal [[14, 'failure', 'captures/output.txt', 1]], actual['tables']['captures'].map { |row| row.values_at('id', 'name', 'path', 'exit_status') }
    result = child("Hiiro::DB.connection[:todos].where(id:9).update(text:'later'); begin; Hiiro::DB.restore!(#{export.inspect}); rescue Hiiro::DB::ImportError => error; puts JSON.generate(error:error.message,text:Hiiro::TodoItem[9].text); end", env: recovery_env)
    assert_equal 'Recovery conflicts with later write: todos/9', result['error']
    assert_equal 'later', result['text']
    assert_equal bytes, excluded.to_h { |path| [path, File.binread(File.join(@base, path))] }
  end
  def test_existing_sql_schema_upgrade_and_legacy_pr_import_preserve_ids_and_unknown_columns
    script = <<~RUBY
      require 'sequel'
      db=Sequel.connect(ENV.fetch('HIIRO_TEST_DB'))
      db.create_table(:todos) { Integer :id, primary_key:true; String :text, null:false; String :status, default:'not_started' }
      db[:todos].insert(id:9,text:'existing')
      db.create_table(:prs) { primary_key :id; Integer :number; String :repo; String :title; String :custom }
      db[:prs].insert(id:11,number:2,repo:'old/repo',title:'existing PR',custom:'retained')
      db.create_table(:pinned_prs) { primary_key :id; Integer :number; String :repo; String :title }
      db[:pinned_prs].insert(id:13,number:3,repo:'new/repo',title:'legacy pin')
      puts 'created'
    RUBY
    output, errors, status = Open3.capture3(@env, RbConfig.ruby, '-e', script, chdir: ROOT)
    assert status.success?, errors
    assert_equal "created\n", output
    source('todo.yml', {'next_id' => 100, 'todos' => [{'id' => 9, 'text' => 'existing'}]})
    export = File.join(@home, 'sql-export.json')
    result = child("Hiiro::DB.migrate!; Hiiro::DB.connection[:todos].where(id:9).delete; id=Hiiro::DB.connection[:todos].insert(text:'after delete'); Hiiro::DB.export!(#{export.inspect}); puts JSON.generate(todo_id:id,custom:Hiiro::PinnedPr[11][:custom],pr:Hiiro::PinnedPr[13].values.slice(:id,:repo,:number,:title),legacy:Hiiro::DB.connection[:pinned_prs].all)")
    assert_equal 100, result['todo_id']
    assert_equal 'retained', result['custom']
    assert_equal({'id' => 13, 'repo' => 'new/repo', 'number' => 3, 'title' => 'legacy pin'}, result['pr'])
    assert_equal [{'id' => 13, 'number' => 3, 'repo' => 'new/repo', 'title' => 'legacy pin'}], result['legacy']
    env = @env.merge('HIIRO_TEST_DB' => "sqlite://#{@home}/recovered-sql.sqlite")
    result = child("Hiiro::DB.restore!(#{export.inspect}); puts JSON.generate(custom:Hiiro::PinnedPr[11][:custom],legacy:Hiiro::DB.connection[:pinned_prs].all,resources:Hiiro::DB.connection[:todos].all)", env: env)
    assert_equal 'retained', result['custom']
    assert_equal [{'id' => 13, 'number' => 3, 'repo' => 'new/repo', 'title' => 'legacy pin'}], result['legacy']
    assert_equal 100, result['resources'].first['id']
  end

  def test_actual_cli_plan_migrate_repeat_export_restore_keeps_definition_bytes_and_exact_rows
    source('todo.yml', {'next_id' => 75, 'todos' => [{'id' => 8, 'text' => 'cli record', 'task_name' => 'alpha', 'subtask_name' => 'child'}]})
    source('tasks/tasks.yml', {'tasks' => [{'id' => 15, 'name' => 'alpha'}]})
    source('pins/h-link', {'literal' => 'false', 'boolean' => false})
    source('apps.yml', {'apps' => {'editor' => '/tmp/editor'}})
    source('projects.yml', {'proj' => '/tmp/project'})
    source('pane_homes.yml', {'work' => {'task' => 'alpha', 'tree' => '/tmp/work'}})
    source('tasks/assignments.yml', {'/tmp/work' => 'alpha'})
    definition = source('services.yml', {'untouched' => {'command' => 'sleep 60'}})
    original = File.binread(definition)
    export = File.join(@home, 'cli-export.json')
    run_cli = lambda do |*args, env: @env, success: true|
      out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', LIB, File.join(ROOT, 'bin/h-db'), *args, chdir: ROOT)
      assert_equal success, status.success?, "#{out}\n#{err}"
      out + err
    end
    run_cli.call('plan')
    assert_equal [], snapshot['todos']
    run_cli.call('migrate')
    child("Hiiro::TodoItem[8].update(text:'later CLI',status:'started'); row=Hiiro::TodoItem.create(text:'new CLI record'); puts JSON.generate(id:row.id)")
    run_cli.call('migrate')
    assert_equal [8, 75], snapshot['todos'].map { |row| row['id'] }
    run_cli.call('export', export)
    exported = File.binread(export)
    run_cli.call('export', export, success: false)
    assert_equal exported, File.binread(export)
    recovery_env = @env.merge('HIIRO_TEST_DB' => "sqlite://#{@home}/cli-recovered.sqlite")
    run_cli.call('restore', export, env: recovery_env)
    reexport = export + '.recovered'
    run_cli.call('export', reexport, env: recovery_env)
    assert_equal JSON.parse(File.binread(export))['payload'], JSON.parse(File.binread(reexport))['payload']
    observed = child("puts JSON.generate(todo:Hiiro::TodoItem[8].values.slice(:id,:text,:task_name,:subtask_name),pin:Hiiro::PinRecord.find_key('h-link','literal').value,apps:Hiiro::AppRecord.all.map{|r| [r.name,r.path]},projects:Hiiro::Project.all.map{|r| [r.name,r.path]},assignment:Hiiro::Assignment.all.map{|r| [r.worktree,r.branch]},capture:Hiiro::DB.connection[:invocations].count)", env: recovery_env)
    assert_equal({'id' => 8, 'text' => 'later CLI', 'task_name' => 'alpha', 'subtask_name' => 'child'}, observed['todo'])
    assert_equal 'false', observed['pin']
    assert_equal [['editor', '/tmp/editor']], observed['apps']
    assert_equal [['proj', '/tmp/project']], observed['projects']
    assert_equal [['/tmp/work', 'alpha']], observed['assignment']
    assert_equal 2, observed['capture']
    assert_equal original, File.binread(definition)
  end

  def test_duplicate_yaml_mapping_fields_are_rejected_without_losing_either_source_value
    path = source('pins/cmd', {})
    File.write(path, "key: first\nkey: second\n")
    original = File.binread(path)
    result = child("plan=Hiiro::DB.migration_plan(only:[:pins]); puts JSON.generate(errors:plan[:errors],pins:Hiiro::PinRecord.count,complete:Hiiro::DB.migrated?)")
    assert_match(/Duplicate YAML mapping key: key/, result['errors'].join)
    assert_equal 0, result['pins']
    assert_equal false, result['complete']
    assert_equal original, File.binread(path)
  end

  def test_invalid_task_name_is_an_inspectable_plan_error_before_filename_resolution
    source('tasks/tasks.yml', {'tasks' => [{'id' => 7, 'name' => 42}]})
    source('tasks/task_alpha.yml', {'name' => 'alpha', 'windows' => []})
    result = child("plan=Hiiro::DB.migration_plan(only:[:tasks]); puts JSON.generate(errors:plan[:errors],tasks:Hiiro::TaskRecord.count,complete:Hiiro::DB.migrated?)")
    assert_match(/task name must be a string/, result['errors'].join)
    assert_equal 0, result['tasks']
    assert_equal false, result['complete']
  end

  def test_failed_fresh_verification_never_completes_and_retry_preserves_later_writes
    path = source('todo.yml', {'todos' => [{'id' => 7, 'text' => 'original'}]})
    original = File.binread(path)
    result = child(<<~RUBY)
      class << Hiiro::DB
        def verify_committed!(*); raise Hiiro::DB::ImportError, 'simulated fresh reload failure'; end
      end
      begin; Hiiro::DB.migrate!; rescue Hiiro::DB::ImportError => error; failure=error.message; end
      puts JSON.generate(error:failure,complete:Hiiro::DB.migrated?,todos:Hiiro::TodoItem.order(:id).all.map{|row|[row.id,row.text]},accepted:Hiiro::DB.connection[:migration_sources].count)
    RUBY
    assert_match(/Committed but persistence verification failed/, result['error'])
    assert_equal false, result['complete']
    assert_equal [[7, 'original']], result['todos']
    assert_equal 1, result['accepted']
    assert_equal original, File.binread(path)
    result = child(<<~RUBY)
      Hiiro::TodoItem[7].update(text:'later'); Hiiro::TodoItem.create(text:'new')
      report=Hiiro::DB.migrate!
      puts JSON.generate(complete:Hiiro::DB.migrated?,todos:Hiiro::TodoItem.order(:id).all.map{|row|[row.id,row.text]},status:report.first[:status])
    RUBY
    assert_equal true, result['complete']
    assert_equal [[7, 'later'], [8, 'new']], result['todos']
    assert_equal 'previously-applied', result['status']
  end

  def test_unresolved_legacy_pin_is_rejected_and_reliable_null_source_preserves_type
    source('pins/cmd', {'safe' => true})
    result = child("Hiiro::PinRecord.create(command:'cmd',key:'ambiguous',value_json:'42',value_format:'legacy'); plan=Hiiro::DB.migration_plan(only:[:pins]); puts JSON.generate(errors:plan[:errors],rows:Hiiro::PinRecord.all.map(&:values),complete:Hiiro::DB.migrated?)")
    assert_match(/Ambiguous legacy pins lack reliable typed source/, result['errors'].join)
    assert_equal ['ambiguous'], result['rows'].map { |row| row['key'] }
    assert_equal false, result['complete']
    source('pins/cmd', {'ambiguous' => '42', 'nothing' => nil})
    result = child("Hiiro::PinRecord.create(command:'cmd',key:'nothing',value_json:nil,value_format:'legacy'); Hiiro::DB.migrate!(only:[:pins]); puts JSON.generate(pins:Hiiro::PinRecord.order(:key).all.map{|row|[row.key,row.value,row.value_format]})")
    assert_equal [['ambiguous', '42', 'json'], ['nothing', nil, 'json']], result['pins']
  end

  def test_semantic_json_repository_aliases_inline_link_tags_and_workspace_clears_are_preserved
    source('links.yml', [{'id' => 22, 'url' => 'https://example.test', 'tags' => ['doc', 'review']}])
    source('pinned_prs.yml', [
      {'id' => 30, 'repo' => 'github.com/one/repo', 'number' => 1, 'title' => 'kept', 'tmux_session' => 'legacy', 'tags' => ['work']},
      {'id' => 31, 'repo' => 'two/repo', 'number' => 1, 'tmux_session' => 'legacy-two', 'herdr_workspace' => nil}
    ])
    result = child(<<~RUBY)
      Hiiro::DB.connection[:prs].insert(id:30,repo:'one/repo',number:1,title:'kept',pinned:true,tmux_session:'legacy',herdr_workspace:'legacy',tags_json:'[ "work" ]',state:'OPEN')
      Hiiro::DB.migrate!
      puts JSON.generate(prs:Hiiro::PinnedPr.order(:id).all.map{|row|[row.id,row.repo,row.herdr_workspace,row.tmux_session,row.tags_json,row.state]},tags:Hiiro::Link[22].tags)
    RUBY
    assert_equal [[30, 'one/repo', 'legacy', 'legacy', '[ "work" ]', 'OPEN'], [31, 'two/repo', nil, 'legacy-two', nil, nil]], result['prs']
    assert_equal ['doc', 'review'], result['tags']
    result = child("Hiiro::DB.migrate!; puts JSON.generate(workspace:Hiiro::PinnedPr[31].herdr_workspace,tags:Hiiro::Link[22].tags)")
    assert_nil result['workspace']
    assert_equal ['doc', 'review'], result['tags']
  end
end
