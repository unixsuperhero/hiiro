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

  LOCAL = %i[task worktree herdr_workspace].freeze

  def ref(number = 7, repo = 'team/one') = Hiiro::PullRequestReference.new(number: number, repo: Hiiro::RepositoryIdentity.parse(repo))

  # Tracks with local preferences; other columns are set as stored data.
  def track(number = 7, repo = 'team/one', **attrs)
    record, = @manager.track(ref(number, repo), **attrs.slice(*LOCAL))
    rest = attrs.reject { |key, _| LOCAL.include?(key) }
    record.update(rest) unless rest.empty?
    record.refresh
  end

  def snapshot(number = 7, repo = 'team/one', head: 'h1', checks: [RUN], reviews: [], checks_complete: true,
               reviews_complete: true, title: 'fresh', state: 'OPEN', at: Time.now.utc)
    part = Hiiro::PrSnapshot::Part
    Hiiro::PrSnapshot.new(reference: ref(number, repo), head_sha: head, fetched_at: at.iso8601(6),
      fields: { 'title' => title, 'state' => state, 'url' => ref(number, repo).url },
      checks: part.new(nodes: checks, complete: checks_complete, error: checks_complete ? nil : 'checks: page 2 failed: HTTP 502'),
      reviews: part.new(nodes: reviews, complete: reviews_complete, error: reviews_complete ? nil : 'reviews: 50 of 60 fetched'))
  end

  # A fetcher that answers from a block, which may also act between the refresh's read and write.
  def stub_fetcher(freeze: false, &answer)
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) { |refs| refs.to_h { |r| [r, answer.call(r)] } }
    @manager.instance_variable_set(:@fetcher, fetcher)
    @manager.instance_variable_set(:@code_freeze_active, freeze)
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

  def test_track_and_unpin_use_repository_qualified_identity
    first = track(task: 'work', tags_json: '["keep"]')
    second = track(7, 'team/two')
    again, outcome = @manager.track(ref)
    assert_equal [:already, first.id, first.slot, first.pinned_at, ['keep'], 'work'],
                 [outcome, again.id, again.slot, again.pinned_at, again.tags, again.task]
    assert_equal ['team/one#7', 'team/two#7'], @manager.load_pinned.map { |pr| pr.reference.to_s }
    error = assert_raises(Hiiro::Error) { @manager.unpin(7) }
    assert_equal 'Ambiguous PR #7 (team/one#7, team/two#7); use owner/name#7 or its URL', error.message
    assert @manager.unpin('https://github.com/team/one/pull/7')
    assert_equal [[second.id, 'team/two', nil]], @manager.load_pinned.map { |pr| [pr.id, pr.repo, pr.title] }
    assert_raises(Hiiro::Error) { @manager.track(Hiiro::PullRequestReference.parse('9')) }
  end

  def test_track_promotes_tracked_record_without_replacing_its_metadata
    tracked = Hiiro::PinnedPr.create(number: 7, repo: 'team/one', task: 'retained', branch: 'old', tmux_json: '{"window":3}', title: 'remote')
    promoted, outcome = @manager.track(ref, task: 'ignored')
    assert_equal [:promoted, tracked.id], [outcome, promoted.id]
    assert_equal ['retained', 'old', '{"window":3}', true, 1, 'remote'], [promoted.task, promoted.branch, promoted.tmux_json, promoted.pinned, promoted.slot, promoted.title]
  end

  def test_reads_do_not_allocate_slots_or_fall_back_to_unqualified_rows
    unknown = Hiiro::PinnedPr.create(number: 7, pinned: true, task: 'unknown')
    assert_nil @manager.find('https://github.com/team/one/pull/7')
    assert_equal [unknown.id], @manager.load_pinned.map(&:id)
    assert_nil unknown.refresh.slot
    qualified = track
    assert_equal qualified.id, @manager.find('https://github.com/team/one/pull/7').id
    assert_equal qualified.id, @manager.find('team/one#7').id
    assert_raises(Hiiro::Error) { @manager.find(7) }
  end

  def test_interleaved_array_mutations_preserve_other_records_and_fields
    first = track(task: 'keep', tags_json: '["initial"]', depends_on_json: '["team/one#3"]')
    stale = @manager.load_pinned.first
    @manager.change_tags(first, add: ['concurrent'])
    second = track(8)
    @manager.change_dependencies(stale, add: [ref(4, 'team/two')])
    @manager.change_tags(stale, add: ['edited'])
    current = first.refresh
    assert_equal ['initial', 'concurrent', 'edited'], current.tags
    assert_equal ['team/one#3', 'team/two#4'], current.depends_on
    assert_equal 'keep', current.task
    assert_equal [first.id, second.id], @manager.load_pinned.map(&:id)
    assert_raises(Hiiro::Error) { @manager.change_dependencies(first, add: [Hiiro::PullRequestReference.parse('5')]) }
    @manager.change_dependencies(first, remove: [ref(3)])
    assert_equal ['team/two#4'], first.refresh.depends_on
  end

  def test_bulk_editor_changes_only_edited_fields_and_original_selected_rows
    first = track(task: 'before', tags_json: '["old"]')
    second = track(8)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    rows = @manager.edit_rows(baseline.values.map { |entry| entry[:record] })
    rows.first['tags'] = ['edited']
    rows.first['depends_on'] = ['team/two#8']
    first.update(task: 'concurrent')
    third = track(9)
    @manager.apply_edits(rows, baseline: baseline)
    assert_equal [['edited'], ['team/two#8'], 'concurrent'], [first.refresh.tags, first.depends_on, first.task]
    deletion_baseline = @manager.edit_baseline(@manager.load_pinned.reject { |pr| pr.id == third.id })
    @manager.apply_edits(@manager.edit_rows([first]), baseline: deletion_baseline)
    assert_equal [first.id, third.id], @manager.load_pinned.map(&:id)
    assert_nil Hiiro::PinnedPr[second.id]
  end

  def test_bulk_editor_rejects_unqualified_dependencies_but_keeps_legacy_numbers
    first = track(depends_on_json: '[12]')
    baseline = @manager.edit_baseline(@manager.load_pinned)
    rows = @manager.edit_rows([first])
    rows.first['depends_on'] = [12, 13]
    error = assert_raises(Hiiro::Error) { @manager.apply_edits(rows, baseline: baseline) }
    assert_equal 'Invalid depends_on: use owner/name#N entries', error.message
    rows.first['depends_on'] = [12, 'team/one#13']
    @manager.apply_edits(rows, baseline: baseline)
    assert_equal [12, 'team/one#13'], first.refresh.depends_on
  end

  def test_bulk_editor_conflicts_roll_back_other_edits_and_refuse_unknown_ids
    first = track(tags_json: '["old"]')
    second = track(8, 'team/one', task: 'before')
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
    first = track(tags_json: '["old"]')
    baseline = @manager.edit_baseline(@manager.load_pinned)
    first.update(task: 'concurrent')
    assert_raises(Hiiro::Error) { @manager.apply_edits([], baseline: baseline) }
    rows = @manager.edit_rows(baseline.values.map { |entry| entry[:record] })
    rows.first['tags'] = ['edited']
    @manager.unpin(first)
    assert_raises(Hiiro::Error) { @manager.apply_edits(rows, baseline: baseline) }
    replacement = track(8)
    assert_equal [[replacement.id, 8]], @manager.load_pinned.map { |pr| [pr.id, pr.number] }
  end

  def test_partial_editor_fields_distinguish_omission_null_and_false
    first = track(task: 'keep', worktree: 'tree', herdr_workspace: 'workspace', tags_json: '["old"]', assigned: true, authored: true)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    @manager.apply_edits([{ 'id' => first.id, 'tags' => nil, 'assigned' => false }], baseline: baseline)
    first.refresh
    assert_equal [[], false, true, 'keep', 'tree', 'workspace', 'team/one'], [first.tags, first.assigned, first.authored, first.task, first.worktree, first.herdr_workspace, first.repo]
    duplicate_rows = [{ 'id' => first.id, 'task' => 'must not save' }, { 'id' => first.id }]
    assert_raises(Hiiro::Error) { @manager.apply_edits(duplicate_rows, baseline: baseline) }
    assert_equal 'keep', first.refresh.task
  end

  def test_refresh_writes_only_remote_fields_and_keeps_local_changes_made_between_read_and_write
    first = track(task: 'keep', tags_json: '["old"]', depends_on_json: '["team/one#8"]')
    deleted = track(9)
    other = track(7, 'team/two', title: 'untouched')
    stale = @manager.load_pinned
    stub_fetcher do |r|
      if r == first.reference
        @manager.change_tags(first, add: ['concurrent'])
        Hiiro::PinnedPr.where(id: first.id).update(task: 'moved')
        @manager.unpin(deleted)
        snapshot(title: 'fresh', state: 'MERGED')
      elsif r == deleted.reference
        snapshot(9, title: 'deleted')
      else
        Hiiro::PrSnapshot::Failure.new(reference: r, error: 'HTTP 502')
      end
    end
    report = @manager.refresh(stale, force: true)
    first.refresh
    assert_equal ['MERGED', 'fresh', ['old', 'concurrent'], ['team/one#8'], 'moved', 'fresh'],
                 [first.state, first.title, first.tags, first.depends_on, first.task, first.refresh_outcome]
    assert_equal [first.id, other.id], @manager.load_pinned.map(&:id)
    assert_equal ['untouched', 'unknown', 'HTTP 502'], [other.refresh.title, other.refresh_outcome, other.refresh_error]
    assert_equal ['lint'], Hiiro::CheckRun.for_pr(first.id).map(&:name)
    assert_equal [[first.id], [], [other.id]], [report.fresh, report.incomplete, report.failed].map { |list| list.map { |pr, _| pr.id } }
  end

  def test_failed_refresh_keeps_last_observation_as_stale_and_never_green
    first = track
    stub_fetcher { |r| snapshot(head: 'abc1234def', reviews: [{ 'author' => { 'login' => 'a' }, 'state' => 'APPROVED' }]) }
    @manager.refresh([first], force: true)
    first.refresh
    assert_equal ['fresh', 'abc1234def', true, true, true], [first.refresh_outcome, first.head_sha, first.checks_complete, first.reviews_complete, first.green?]
    observed = first.values.slice(:title, :state, :head_sha, :fetched_at, :check_runs_json, :checks_json, :reviews_json, :review_nodes_json)
    stub_fetcher { |r| Hiiro::PrSnapshot::Failure.new(reference: r, error: 'head changed during refresh (abc1234 → def5678 at checks page 2)') }
    @manager.refresh([first], force: true)
    first.refresh
    assert_equal observed, first.values.slice(*observed.keys)
    assert_equal ['stale', 'head changed during refresh (abc1234 → def5678 at checks page 2)', false],
                 [first.refresh_outcome, first.refresh_error, first.green?]
    assert_equal [], @manager.apply_filters([first], OpenStruct.new(green: true))
  end

  def test_incomplete_successes_are_stored_as_partial_and_never_green
    first = track
    many = Array.new(150) { |i| RUN.merge('name' => "c#{i}") }
    stub_fetcher { |r| snapshot(checks: many.first(100), checks_complete: false) }
    @manager.refresh([first], force: true)
    first.refresh
    assert_equal ['fresh', false, 100, 0, false, 'checks: page 2 failed: HTTP 502'],
                 [first.refresh_outcome, first.checks_complete, first.check_summary.success, first.check_summary.failed, first.green?, first.refresh_error]
    assert_equal({ 'total' => 100, 'success' => 100, 'pending' => 0, 'failed' => 0, 'frozen' => 0, 'truncated' => true }, first.checks)
    stub_fetcher { |r| snapshot(checks: many, reviews_complete: false) }
    @manager.refresh([first], force: true)
    refute first.refresh.green?
    stub_fetcher { |r| snapshot(checks: many) }
    @manager.refresh([first], force: true)
    assert first.refresh.green?
    assert_equal 150, Hiiro::CheckRun.for_pr(first.id).length
  end

  def test_older_snapshot_does_not_replace_a_newer_one
    first = track
    newer = snapshot(title: 'newer', at: Time.now.utc + 60)
    @manager.instance_variable_set(:@code_freeze_active, false)
    @manager.apply_snapshot(first, newer)
    @manager.apply_snapshot(first, snapshot(title: 'older', checks: [], at: Time.now.utc))
    @manager.record_failure(first, 'late failure', Time.now.utc.iso8601(6))
    first.refresh
    assert_equal ['newer', 'fresh', nil, ['lint']], [first.title, first.refresh_outcome, first.refresh_error, Hiiro::CheckRun.for_pr(first.id).map(&:name)]
  end

  def test_freeze_policy_leaves_raw_contexts_unchanged
    freeze = { '__typename' => 'StatusContext', 'context' => 'ISC code freeze', 'state' => 'FAILURE' }
    first = track
    stub_fetcher(freeze: false) { |r| snapshot(checks: [RUN, freeze]) }
    @manager.refresh([first], force: true)
    first.refresh
    assert_equal [RUN, freeze], first.check_runs
    assert_equal [false, 2, 0, true], [first.freeze_active, first.check_summary.success, first.check_summary.failed, first.green?]
    assert_equal 1, first.checks['failed']
    Hiiro::PinnedPr.where(id: first.id).update(freeze_active: true)
    assert_equal [1, 1, true, false], [first.refresh.check_summary.failed, first.check_summary.frozen, first.check_summary.only_frozen?, first.green?]
    Hiiro::PinnedPr.where(id: first.id).update(freeze_active: nil)
    assert_equal [1, false], [first.refresh.check_summary.failed, first.green?]
  end

  def test_unqualified_rows_are_reported_not_refreshed
    legacy = Hiiro::PinnedPr.create(number: 7, pinned: true, state: 'OPEN', title: 'legacy')
    calls = []
    stub_fetcher { |r| calls << r; snapshot }
    report = @manager.refresh([legacy], force: true)
    assert_equal [[], [[legacy.id, 'no repository; track it again by URL']]], [calls, report.unqualified.map { |pr, why| [pr.id, why] }]
    assert_equal ['legacy', nil], [legacy.refresh.title, legacy.refresh_outcome]
  end

  def test_known_empty_refresh_clears_only_its_own_checks
    first = track(task: 'keep')
    second = track(7, 'team/two')
    stub_fetcher { |r| snapshot(r.number, r.repo.path, checks: [RUN.merge('name' => r.repo.name)]) }
    @manager.refresh([first, second], force: true)
    stub_fetcher { |r| snapshot(checks: []) }
    @manager.refresh([first], force: true)
    assert_equal ['fresh', 'keep', [], true, nil], [first.refresh.title, first.task, first.check_runs, first.checks_complete, first.check_summary]
    assert_equal [], Hiiro::CheckRun.for_pr(first.id).map(&:name)
    assert_equal ['two'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
  end

  def test_check_replacement_deletes_only_exact_pr_owner
    first = track
    second = track(7, 'team/two')
    Hiiro::CheckRun.upsert_for_pr(first.id, [RUN])
    Hiiro::CheckRun.upsert_for_pr(second.id, [RUN.merge('name' => 'other')])
    legacy = Hiiro::CheckRun.create(pr_number: 7, name: 'unowned')
    Hiiro::CheckRun.upsert_for_pr(first.id, [RUN.merge('name' => 'updated')])
    assert_equal ['updated'], Hiiro::CheckRun.for_pr(first.id).map(&:name)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_equal ['unowned', nil], [legacy.refresh.name, legacy.pr_id]
    @manager.unpin(first)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_equal 'unowned', legacy.refresh.name
  end

  def test_editor_deletion_rejects_changed_tags_but_not_a_remote_refresh
    first = track
    second = track(7, 'team/two')
    Hiiro::CheckRun.upsert_for_pr(second.id, [RUN.merge('name' => 'other')])
    baseline = @manager.edit_baseline(@manager.load_pinned)
    tag = Hiiro::Tag.create(name: 'attached', taggable_type: 'PinnedPr', taggable_id: first.id.to_s)
    other_tag = Hiiro::Tag.create(name: 'other', taggable_type: 'PinnedPr', taggable_id: second.id.to_s)
    assert_raises(Hiiro::Error) { @manager.apply_edits(@manager.edit_rows([second]), baseline: baseline) }
    assert_equal [first.id, second.id], @manager.load_pinned.map(&:id)
    baseline = @manager.edit_baseline(@manager.load_pinned)
    stub_fetcher { |r| snapshot(title: 'refreshed meanwhile') }
    @manager.refresh([first], force: true)
    @manager.remove([first.id], baseline: baseline)
    assert_nil Hiiro::PinnedPr[first.id]
    assert_equal ['other'], Hiiro::Tag.for(second).select_map(:name)
    assert_equal ['other'], Hiiro::CheckRun.for_pr(second.id).map(&:name)
    assert_empty Hiiro::CheckRun.for_pr(first.id)
    assert_nil Hiiro::Tag[tag.id]
  ensure
    Hiiro::Tag.where(id: [tag&.id, other_tag&.id].compact).delete
  end

  def test_startup_migration_qualifies_only_unambiguous_legacy_dependencies
    db = Sequel.sqlite
    Hiiro::PinnedPr.create_table!(db)
    db[:prs].insert(id: 1, number: 10, repo: 'team/one', depends_on_json: '[11, 12, 13, 14]')
    db[:prs].insert(id: 2, number: 11, repo: 'team/one')
    db[:prs].insert(id: 3, number: 12, repo: 'team/one')
    db[:prs].insert(id: 4, number: 12, repo: 'team/two')
    db[:prs].insert(id: 5, number: 13, repo: 'team/two')
    db[:prs].insert(id: 6, number: 20, url: 'https://github.com/team/three/pull/20', depends_on_json: '[11]')
    db[:prs].insert(id: 7, number: 21, depends_on_json: '[11]')
    2.times { Hiiro::PinnedPr.migrate!(db) }
    assert_equal [['team/one', '["team/one#11",12,13,14]'], ['team/three', '[11]'], [nil, '[11]']],
                 db[:prs].where(id: [1, 6, 7]).order(:id).select_map([:repo, :depends_on_json])
  ensure
    db&.disconnect
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
