require 'test_helper'
require 'open3'
require 'rbconfig'

class PinnedPRManagerTest < Minitest::Test
  RUN = { '__typename' => 'CheckRun', 'name' => 'lint', 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS' }.freeze

  def setup
    Hiiro::CheckRun.dataset.delete
    Hiiro::PinnedPr.dataset.delete
    @manager = Hiiro::PinnedPRManager.new
  end

  def teardown
    Hiiro::CheckRun.dataset.delete
    Hiiro::PinnedPr.dataset.delete
  end

  def pin(number = 7, repo = 'team/one', **attrs)
    @manager.pin(Hiiro::Git::Pr.new(number: number, repo: repo, state: 'OPEN', **attrs))
  end

  def test_cleared_canonical_workspace_survives_fresh_process_startup
    Dir.mktmpdir('hiiro-pr-workspace-') do |dir|
      database = File.join(dir, 'records.db')
      db = Sequel.sqlite(database)
      db.create_table(:prs) { primary_key :id; Integer :number; String :repo; TrueClass :pinned; String :tmux_session }
      db[:prs].insert(id: 42, number: 7, repo: 'team/one', pinned: true, tmux_session: 'legacy-workspace')
      db.disconnect
      environment = { 'HOME' => dir, 'HIIRO_TEST_DB' => "sqlite://#{database}" }
      load_path = File.expand_path('../../lib', __dir__)
      first_startup = <<~RUBY
        Hiiro::DB.setup!
        manager = Hiiro::PinnedPRManager.new
        pr = Hiiro::PinnedPr[42]
        puts JSON.dump([pr.id, pr.herdr_workspace, pr.tmux_session])
        manager.apply_edits([{ 'id' => 42, 'herdr_workspace' => nil }], baseline: manager.edit_baseline([pr]))
        puts JSON.dump([pr.refresh.id, pr.herdr_workspace, pr.tmux_session, pr.to_git_pr.herdr_workspace])
      RUBY
      stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, '-I', load_path, '-rhiiro', '-e', first_startup)
      assert status.success?, stderr
      assert_equal [[42, 'legacy-workspace', 'legacy-workspace'], [42, nil, 'legacy-workspace', nil]], stdout.lines.map { |line| JSON.parse(line) }
      second_startup = 'Hiiro::DB.setup!; pr = Hiiro::PinnedPr[42]; puts JSON.dump([pr.id, pr.herdr_workspace, pr.tmux_session, pr.to_git_pr.herdr_workspace])'
      stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, '-I', load_path, '-rhiiro', '-e', second_startup)
      assert status.success?, stderr
      assert_equal [42, nil, 'legacy-workspace', nil], JSON.parse(stdout)
    end
  end

  def test_pin_and_unpin_use_repository_qualified_identity
    first = pin(title: 'first', tags: ['keep'], depends_on: [8], task: 'work')
    identity = [first.id, first.slot, first.pinned_at]
    second = pin(7, 'team/two', title: 'other repo')
    again = pin(title: 'refreshed', tags: ['stale'], depends_on: [9], task: 'stale')

    assert_equal identity, [again.id, again.slot, again.pinned_at]
    assert_equal ['keep'], again.tags
    assert_equal [8], again.depends_on
    assert_equal 'work', again.task
    assert_raises(Hiiro::Error) { @manager.unpin(7) }
    assert @manager.unpin('https://github.com/team/one/pull/7')
    assert_equal [[second.id, 'team/two', 'other repo']], @manager.load_pinned.map { |pr| [pr.id, pr.repo, pr.title] }
  end

  def test_pin_promotes_tracked_record_without_replacing_its_metadata
    tracked = Hiiro::PinnedPr.create(number: 7, repo: 'team/one', task: 'retained', branch: 'old', tmux_json: '{"window":3}')
    promoted = pin(title: 'promoted')
    assert_equal tracked.id, promoted.id
    assert_equal ['retained', 'old', '{"window":3}', true, 1], [promoted.task, promoted.branch, promoted.tmux_json, promoted.pinned, promoted.slot]
  end

  def test_reads_do_not_allocate_slots_or_fall_back_to_unqualified_rows
    unknown = Hiiro::PinnedPr.create(number: 7, pinned: true, task: 'unknown')
    assert_nil @manager.find('https://github.com/team/one/pull/7')
    assert_equal [unknown.id], @manager.load_pinned.map(&:id)
    assert_nil unknown.refresh.slot
    qualified = pin
    assert_equal qualified.id, @manager.find('https://github.com/team/one/pull/7').id
    assert_raises(Hiiro::Error) { @manager.find(7) }
  end

  def test_interleaved_array_mutations_preserve_other_records_and_fields
    first = pin(tags: ['initial'], depends_on: [3], task: 'keep')
    stale = @manager.load_pinned.first
    @manager.change_tags(first, add: ['concurrent'])
    second = pin(8, 'team/one', title: 'new')
    @manager.change_dependencies(stale, add: [4])
    @manager.change_tags(stale, add: ['edited'])
    current = first.refresh
    assert_equal ['initial', 'concurrent', 'edited'], current.tags
    assert_equal [3, 4], current.depends_on
    assert_equal 'keep', current.task
    assert_equal [first.id, second.id], @manager.load_pinned.map(&:id)
  end

  def test_bulk_editor_changes_only_edited_fields_and_original_selected_rows
    first = pin(tags: ['old'], task: 'before')
    second = pin(8)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    rows = @manager.edit_rows(baseline.values.map { |entry| entry[:record] })
    rows.first['tags'] = ['edited']
    first.update(task: 'concurrent')
    third = pin(9)
    @manager.apply_edits(rows, baseline: baseline)
    assert_equal [['edited'], 'concurrent'], [first.refresh.tags, first.task]
    deletion_baseline = @manager.edit_baseline(@manager.load_pinned.reject { |pr| pr.id == third.id })
    @manager.apply_edits(@manager.edit_rows([first]), baseline: deletion_baseline)
    assert_equal [first.id, third.id], @manager.load_pinned.map(&:id)
    assert_nil Hiiro::PinnedPr[second.id]
  end

  def test_bulk_editor_conflicts_roll_back_other_edits_and_refuse_unknown_ids
    first = pin(tags: ['old'])
    second = pin(8, 'team/one', task: 'before')
    baseline = @manager.edit_baseline(@manager.load_pinned)
    rows = @manager.edit_rows(baseline.values.map { |entry| entry[:record] })
    rows.first['task'] = 'edited'
    rows.last['task'] = 'edited'
    second.update(task: 'concurrent')
    assert_raises(Hiiro::Error) { @manager.apply_edits(rows, baseline: baseline) }
    assert_equal [nil, 'concurrent'], [first.refresh.task, second.refresh.task]
    assert_raises(Hiiro::Error) { @manager.apply_edits([{ 'id' => 999 }], baseline: baseline) }
    assert_equal [first.id, second.id], @manager.load_pinned.map(&:id)
  end

  def test_bulk_editor_does_not_delete_concurrently_changed_rows_or_recreate_removed_rows
    first = pin(tags: ['old'])
    baseline = @manager.edit_baseline(@manager.load_pinned)
    first.update(task: 'concurrent')
    assert_raises(Hiiro::Error) { @manager.apply_edits([], baseline: baseline) }
    rows = @manager.edit_rows(baseline.values.map { |entry| entry[:record] })
    rows.first['tags'] = ['edited']
    @manager.unpin(first)
    assert_raises(Hiiro::Error) { @manager.apply_edits(rows, baseline: baseline) }
    replacement = pin(8, 'team/one', title: 'new')
    assert_equal [[replacement.id, 8]], @manager.load_pinned.map { |pr| [pr.id, pr.number] }
  end

  def test_partial_editor_fields_distinguish_omission_null_and_false
    first = pin(tags: ['old'], task: 'keep', worktree: 'tree', herdr_workspace: 'workspace', assigned: true, authored: true)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    @manager.apply_edits([{ 'id' => first.id, 'tags' => nil, 'assigned' => false }], baseline: baseline)
    first.refresh
    assert_equal [[], false, true, 'keep', 'tree', 'workspace', 'team/one'], [first.tags, first.assigned, first.authored, first.task, first.worktree, first.herdr_workspace, first.repo]
    duplicate_rows = [{ 'id' => first.id, 'task' => 'must not save' }, { 'id' => first.id }]
    assert_raises(Hiiro::Error) { @manager.apply_edits(duplicate_rows, baseline: baseline) }
    assert_equal 'keep', first.refresh.task
  end


  def test_refresh_preserves_concurrent_metadata_and_does_not_recreate_deleted_pr
    first = pin(tags: ['old'], depends_on: [8], task: 'keep', check_runs: [RUN])
    deleted = pin(9)
    stale = @manager.load_pinned
    @manager.change_tags(first, add: ['concurrent'])
    @manager.unpin(deleted)
    third = pin(10)
    infos = { [7, 'team/one'] => { 'state' => 'MERGED', 'title' => 'fresh', 'statusCheckRollup' => [] }, [9, 'team/one'] => { 'state' => 'MERGED', 'title' => 'deleted' } }
    @manager.stub(:batch_fetch_pr_info, infos) do
      @manager.stub(:code_freeze_active?, false) { @manager.refresh_all_status(stale, force: true) }
    end
    first.refresh
    assert_equal ['MERGED', 'fresh', ['old', 'concurrent'], [8], 'keep'], [first.state, first.title, first.tags, first.depends_on, first.task]
    assert_equal [first.id, third.id], @manager.load_pinned.map(&:id)
    assert_empty Hiiro::CheckRun.for_pr(first.id)
    assert_equal 'OPEN', third.refresh.state
  end

  def test_single_refresh_clears_selected_checks_when_fetched_rollup_is_empty
    first = pin(check_runs: [RUN], task: 'keep')
    second = pin(7, 'team/two', check_runs: [RUN.merge('name' => 'other')])
    fetched = Hiiro::Git::Pr.from_gh_json('number' => 7, 'state' => 'OPEN', 'title' => 'fresh', 'statusCheckRollup' => [])
    @manager.stub(:fetch_pr_info, fetched) do
      @manager.stub(:code_freeze_active?, false) { @manager.refresh_status(first, force: true) }
    end
    assert_equal ['fresh', 'keep', nil], [first.refresh.title, first.task, first.check_runs]
    assert_equal [], Hiiro::CheckRun.for_pr(first.id).map(&:name)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
  end


  def test_check_replacement_deletes_only_exact_pr_owner
    first = pin(check_runs: [RUN])
    second = pin(7, 'team/two', check_runs: [RUN.merge('name' => 'other')])
    legacy = Hiiro::CheckRun.create(pr_number: 7, name: 'unowned')
    Hiiro::CheckRun.upsert_for_pr(first.id, [RUN.merge('name' => 'updated')])
    assert_equal ['updated'], Hiiro::CheckRun.for_pr(first.id).map(&:name)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_equal ['unowned', nil], [legacy.refresh.name, legacy.pr_id]
    @manager.unpin(first)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_equal 'unowned', legacy.refresh.name
  end

  def test_editor_deletion_rejects_changed_relations_and_unpin_cleans_only_its_owner
    first = pin(check_runs: [RUN])
    second = pin(7, 'team/two', check_runs: [RUN.merge('name' => 'other')])
    baseline = @manager.edit_baseline(@manager.load_pinned)
    tag = Hiiro::Tag.create(name: 'attached', taggable_type: 'PinnedPr', taggable_id: first.id.to_s)
    other_tag = Hiiro::Tag.create(name: 'other', taggable_type: 'PinnedPr', taggable_id: second.id.to_s)
    assert_raises(Hiiro::Error) { @manager.apply_edits(@manager.edit_rows([second]), baseline: baseline) }
    assert_equal [first.id, second.id], @manager.load_pinned.map(&:id)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    Hiiro::CheckRun.upsert_for_pr(first.id, [RUN.merge('name' => 'updated')])
    assert_raises(Hiiro::Error) { @manager.apply_edits(@manager.edit_rows([second]), baseline: baseline) }
    assert_equal ['attached'], Hiiro::Tag.for(first).select_map(:name)
    @manager.unpin(first)
    assert_equal ['other'], Hiiro::Tag.for(second).select_map(:name)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_nil Hiiro::Tag[tag.id]
  ensure
    Hiiro::Tag.where(id: [tag&.id, other_tag&.id].compact).delete
  end


  def test_old_sql_schema_and_ambiguous_checks_are_preserved
    db = Sequel.sqlite
    db.create_table(:prs) { primary_key :id; Integer :number; String :repo; String :branch; String :task; String :extra; String :check_runs_json }
    db[:prs].insert(id: 42, number: 7, repo: 'team/one', branch: 'feature', task: 'work', extra: 'keep', check_runs_json: JSON.dump([RUN]))
    db[:prs].insert(id: 43, number: 7, repo: 'team/two', check_runs_json: JSON.dump([RUN.merge('name' => 'other')]))
    db.create_table(:pinned_prs) { primary_key :id; Integer :number }
    db[:pinned_prs].insert(id: 9, number: 8)
    db.create_table(:check_runs) { primary_key :id; Integer :pr_number; String :name; String :url; String :status; String :conclusion; String :updated_at }
    db[:check_runs].insert(id: 5, pr_number: 7, name: 'ambiguous')
    Hiiro::CheckRun.migrate!(db)
    Hiiro::PinnedPr.create_table!(db)
    Hiiro::PinnedPr.migrate!(db)
    Hiiro::CheckRun.migrate!(db)
    Hiiro::CheckRun.migrate!(db)
    assert_equal [42, 7, 'team/one', 'feature', 'work', 'keep'], db[:prs].where(id: 42).first.values_at(:id, :number, :repo, :branch, :task, :extra)
    assert_equal [{ id: 9, number: 8 }], db[:pinned_prs].all
    assert_equal [[nil, 'ambiguous'], [42, 'lint'], [43, 'other']], db[:check_runs].order(:id).select_map([:pr_id, :name])
  ensure
    db&.disconnect
  end
end
