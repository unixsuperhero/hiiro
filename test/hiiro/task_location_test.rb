require 'test_helper'

class TaskLocationTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir('hiiro-location-'))
    @code = File.join(@dir, 'code')
    @primary = File.join(@dir, 'primary')
    @override = File.join(@dir, 'override')
    FileUtils.mkdir_p([File.join(@code, 'apps/web'), File.join(@primary, 'apps/web'), @override])
    @task = Hiiro::TaskRecord.create(name: 'location.feat', tree: @code)
    @app = Hiiro::App.new(name: 'web', path: 'apps/web')
  end

  def teardown
    @task.destroy
    FileUtils.remove_entry(@dir)
  end

  def test_directory_precedence_preserves_task_and_invocation
    @task.update(primary_directory: @primary)
    location = Hiiro::TaskLocation.for(@task, invocation_directory: @dir, task_source: :directory)
    assert_equal [@primary, @primary, :primary, :directory],
                 [location.root_directory, location.start_directory, location.source, location.task_source]
    selected = location.for_app(@app)
    assert_equal [@task.id, @dir, @primary, File.join(@primary, 'apps/web'), :app, :directory],
                 [selected.task.id, selected.invocation_directory, selected.root_directory, selected.start_directory, selected.source, selected.task_source]
    overridden = selected.with_directory(@override, source: :frontmatter)
    assert_equal [@primary, @override, 'web', :frontmatter],
                 [overridden.root_directory, overridden.start_directory, overridden.app.name, overridden.source]
    assert_equal @primary, location.start_directory
    assert_raises(FrozenError) { location.instance_variable_set(:@source, :override) }
  end

  def test_taskless_project_root_and_app_do_not_create_a_task
    before = Hiiro::TaskRecord.count
    location = Hiiro::TaskLocation.for(nil, root: @code, root_source: :project, project: 'example', invocation_directory: @dir)
    selected = location.for_app(@app)
    assert_nil selected.task
    assert_equal ['example', :project, :app, File.join(@code, 'apps/web')],
                 [selected.project, selected.root_source, selected.source, selected.start_directory]
    assert_equal before, Hiiro::TaskRecord.count
  end

  def test_explicit_missing_directory_and_app_fail_instead_of_using_root
    location = Hiiro::TaskLocation.for(@task)
    assert_raises(Hiiro::Error) { location.with_directory(File.join(@dir, 'missing'), source: :override) }
    assert_raises(Hiiro::Error) { location.for_app(Hiiro::App.new(name: 'missing', path: 'apps/missing')) }
    assert_raises(Hiiro::Error) { Hiiro::TaskLocation.for(nil, root: File.join(@dir, 'missing')) }
    assert_equal @code, location.start_directory
  end

  def test_explicit_empty_directories_are_rejected_before_expansion
    ['', '   '].each do |blank|
      assert_raises(Hiiro::Error) { Hiiro::TaskLocation.for(@task, root: blank, invocation_directory: @override) }
      assert_raises(Hiiro::Error) { Hiiro::TaskLocation.for(@task, override: blank, invocation_directory: @override) }
      location = Hiiro::TaskLocation.for(@task, invocation_directory: @override)
      assert_raises(Hiiro::Error) { location.with_directory(blank, source: :override) }
    end
    assert_equal @code, Hiiro::TaskLocation.for(@task, root: nil, override: nil).start_directory
  end

  def test_override_does_not_require_or_create_missing_task_home
    @task.update(tree: nil)
    location = Hiiro::TaskLocation.for(@task, invocation_directory: @dir)
    refute Dir.exist?(location.home)
    overridden = location.with_directory(@override, source: :override)
    assert_equal [@task.id, location.home, @override, :override],
                 [overridden.task.id, overridden.root_directory, overridden.start_directory, overridden.source]
    refute Dir.exist?(location.home)
  end

  def test_containment_follows_symlinks_and_rejects_app_escape
    link = File.join(@dir, 'alias')
    File.symlink(@code, link)
    assert Hiiro::TaskLocation.contains?(@code, File.join(link, 'apps/web'))
    refute Hiiro::TaskLocation.contains?(@code, @primary)
    File.symlink(@primary, File.join(@code, 'outside'))
    error = assert_raises(Hiiro::Error) { Hiiro::TaskLocation.for(@task, app: Hiiro::App.new(name: 'outside', path: 'outside')) }
    context = Hiiro::TaskLocation.for(@task, invocation_directory: File.join(link, 'apps/web'))
    assert_equal [@code, File.join(@code, 'apps/web')], [context.root_directory, context.invocation_directory]
    assert_match(/escapes root/, error.message)
  end

  def test_useful_task_paths_and_workspace_label_remain
    location = Hiiro::TaskLocation.for(@task)
    assert_equal [@code, @code, 'location_feat'], [location.worktree_path, location.code_directory, location.workspace_label]
    @task.update(tree: 'branch', session: 'named.session')
    location = Hiiro::TaskLocation.for(@task, work_dir: @dir)
    assert_equal [File.join(@dir, 'branch'), 'named_session'], [location.worktree_path, location.workspace_label]
    @task.update(tree: nil)
    location = Hiiro::TaskLocation.for(@task)
    assert_equal [@task.home, :home], [location.start_directory, location.source]
  end
end
