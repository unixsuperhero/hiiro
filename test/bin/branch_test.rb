require "test_helper"

class BranchTest < Minitest::Test
  def setup
    Hiiro::Branch.dataset.delete
    Hiiro::Tag.where(taggable_type: 'Branch').delete
    @mock_git = MockGit.new
    mock = @mock_git  # capture for closure

    @harness = Hiiro::TestHarness.load_bin("bin/h-branch") do
      define_singleton_method(:git) { mock }
    end
  end



  def test_checkout_with_branch_calls_git_checkout
    @harness.run_subcmd(:co, 'feature-branch')

    assert_equal [['git', 'checkout', 'feature-branch']], @harness.system_calls
  end

  def test_checkout_with_extra_args
    @harness.run_subcmd(:checkout, 'feature-branch', '-b')

    assert_equal [['git', 'checkout', 'feature-branch', '-b']], @harness.system_calls
  end

  def test_remove_with_branch_calls_git_branch_delete
    @harness.run_subcmd(:rm, 'old-branch')

    assert_equal [['git', 'branch', '-d', 'old-branch']], @harness.system_calls
  end

  def test_remove_with_force_flag
    @harness.run_subcmd(:remove, 'old-branch', '-D')

    assert_equal [['git', 'branch', '-d', 'old-branch', '-D']], @harness.system_calls
  end

  def test_duplicate_creates_new_branch_from_source
    @mock_git.current_branch = 'main'
    @harness.run_subcmd(:duplicate, 'new-branch', 'source-branch')

    assert_equal [['git', 'branch', 'new-branch', 'source-branch']], @harness.system_calls
  end

  def test_duplicate_uses_current_branch_as_default_source
    @mock_git.current_branch = 'main'
    @harness.run_subcmd(:duplicate, 'new-branch')

    assert_equal [['git', 'branch', 'new-branch', 'main']], @harness.system_calls
  end

  def test_push_basic
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push)

    call = @harness.system_calls.first
    assert_equal 'git', call[0]
    assert_equal 'push', call[1]
    assert_includes call, 'origin'
    assert_includes call, 'feature:feature'
  end

  def test_push_with_force_flag
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-F')

    call = @harness.system_calls.first
    assert_includes call, '--force'
  end

  def test_push_with_set_upstream_flag
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-u')

    call = @harness.system_calls.first
    assert_includes call, '-u'
  end

  def test_push_with_custom_remote
    @mock_git.current_branch = 'feature'
    @harness.run_subcmd(:push, '-r', 'upstream')

    call = @harness.system_calls.first
    assert_includes call, 'upstream'
    refute_includes call, 'origin'
  end

  def teardown
    Hiiro::Branch.dataset.delete
    Hiiro::Tag.where(taggable_type: 'Branch').delete
  end

  def test_saved_branch_updates_keep_id_note_legacy_and_unknown_payload
    original = Hiiro::Branch.create(name: 'feature', note: 'keep', tmux_json: '{"session":"legacy","extra":42}', herdr_json: '{"workspace":"old","custom":false}', created_at: '2026-01-01')
    other = Hiiro::Branch.create(name: 'other', note: 'untouched')
    tags = Hiiro::Tags.new(:branch)
    tags.add('feature', 'keep')
    manager = BranchManager.new(@harness)
    manager.send(:save_branch, name: 'feature', worktree: 'tree', task: 'task', herdr: { 'workspace' => 'new' }, sha: 'abc')
    updated = Hiiro::Branch[original.id]
    assert_equal ['tree', 'task', 'abc', 'keep', '2026-01-01', '{"session":"legacy","extra":42}', { 'workspace' => 'new', 'custom' => false }], [updated.worktree, updated.task, updated.sha, updated.note, updated.created_at, updated.tmux_json, updated.herdr]
    manager.send(:save_branch, name: 'feature', worktree: 'tree', task: 'task', sha: 'def')
    manager.set_note('edited', 'feature')
    assert_equal [{ 'workspace' => 'new', 'custom' => false }, 'edited', ['keep']], [Hiiro::Branch[original.id].herdr, Hiiro::Branch[original.id].note, tags.get('feature')]
    assert_equal [original.id, other.id], Hiiro::Branch.order(:id).map(&:id)
    assert_equal 'untouched', Hiiro::Branch[other.id].note
  end

  def test_saved_branch_rename_moves_name_keyed_tags_and_removal_is_targeted
    original = Hiiro::Branch.create(name: 'feature', note: 'keep')
    other = Hiiro::Branch.create(name: 'other', note: 'untouched')
    tags = Hiiro::Tags.new(:branch)
    tags.add('feature', 'keep', 'shared')
    tags.add('renamed', 'shared', 'existing')
    tags.add('other', 'unrelated')
    manager = BranchManager.new(@harness)
    assert manager.rename_saved('feature', 'renamed')
    assert_equal ['renamed', 'keep'], Hiiro::Branch[original.id].values.values_at(:name, :note)
    assert_equal %w[existing keep shared], tags.get('renamed').sort
    assert_empty tags.get('feature')
    manager.remove_saved('renamed')
    assert_equal [[other.id, 'other', 'untouched']], Hiiro::Branch.all.map { |record| [record.id, record.name, record.note] }
    assert_equal({ 'other' => ['unrelated'] }, tags.all)
  end

  def test_failed_bulk_tag_editor_does_not_apply_changed_file
    tags = Hiiro::Tags.new(:branch)
    tags.add('main', 'keep')
    @harness.define_singleton_method(:edit_files) { |path| File.write(path, { 'main' => ['changed'], 'develop' => ['new'] }.to_yaml); false }
    output, = capture_io { @harness.run_subcmd(:tag, '-e') }
    assert_includes output, 'Aborted:'
    assert_equal({ 'main' => ['keep'] }, tags.all)
  end

  def test_bulk_tagging_preserves_existing_and_unselected_tags
    tags = Hiiro::Tags.new(:branch)
    tags.add('main', 'keep')
    tags.add('feature-x', 'unselected')
    @harness.define_singleton_method(:edit_files) { |path| File.write(path, { 'main' => ['added'], 'develop' => ['new'] }.to_yaml); true }
    capture_io { @harness.run_subcmd(:tag, '-e') }
    assert_equal %w[added keep], tags.get('main').sort
    assert_equal ['new'], tags.get('develop')
    assert_equal ['unselected'], tags.get('feature-x')
  end

  def test_bulk_tag_editor_preserves_numeric_and_boolean_looking_branch_names
    @mock_git.branches_list = ['0042', 'false']
    Hiiro::Branch.create(name: '0042')
    tags = Hiiro::Tags.new(:branch)
    tags.add('false', 'untouched')
    @harness.define_singleton_method(:edit_files) do |path|
      File.write(path, File.read(path).sub(': []', ":\n- work"))
      true
    end
    output, = capture_io { @harness.run_subcmd(:tag, '-e') }
    assert_includes output, 'Tagged 0042 with: work'
    assert_equal ['work'], tags.get('0042')
    assert_equal ['untouched'], tags.get('false')
  end

  def test_saved_pr_database_failure_is_not_reported_as_missing_pr
    manager = Object.new
    manager.define_singleton_method(:load_pinned) { raise Sequel::DatabaseError, 'PR database unavailable' }
    Hiiro::PinnedPRManager.stub(:new, manager) do
      error = assert_raises(Sequel::DatabaseError) { @harness.run_subcmd(:'for-pr', '42') }
      assert_equal 'PR database unavailable', error.message
    end
  end





  # Mock classes
  class MockGit
    attr_accessor :current_branch, :branches_list

    def initialize
      @current_branch = 'main'
      @branches_list = ['main', 'develop', 'feature-x']
    end

    def branch
      @current_branch
    end

    def branches(sort_by: nil, ignore_case: false)
      @branches_list
    end
  end
end
