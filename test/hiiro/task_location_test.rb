require "test_helper"

class TaskLocationTest < Minitest::Test
  Task = Struct.new(:name, :tree, :primary_directory, :session, keyword_init: true)

  def location(tree: nil, primary: nil, session: nil, **kw)
    Hiiro::TaskLocation.for(Task.new(name: 'feat.x', tree: tree, primary_directory: primary, session: session), work_dir: '/work', **kw)
  end

  def test_worktree_path_relative_and_absolute
    assert_nil location.worktree_path
    assert_equal '/work/feat-x', location(tree: 'feat-x').worktree_path
    assert_equal '/elsewhere/tree', location(tree: '/elsewhere/tree').worktree_path
  end

  def test_code_directory_prefers_primary_directory
    assert_equal '/primary', location(tree: 'feat-x', primary: '/primary').code_directory
    assert_equal '/work/feat-x', location(tree: 'feat-x').code_directory
    assert_nil location.code_directory
  end

  def test_app_directory_needs_app_and_root
    app = Hiiro::App.new(name: 'partners', path: 'partners/partners')
    assert_equal '/work/feat-x/partners/partners', location(tree: 'feat-x', app: app).app_directory
    assert_nil location(app: app).app_directory
    assert_nil location(tree: 'feat-x').app_directory
  end

  def test_start_directory_precedence_and_source
    app = Hiiro::App.new(name: 'a', path: 'apps/a')
    assert_equal [:override, '/o'], [location(tree: 't', app: app, override: '/o').source, location(tree: 't', app: app, override: '/o').start_directory]
    assert_equal [:app, '/work/t/apps/a'], [location(tree: 't', app: app).source, location(tree: 't', app: app).start_directory]
    assert_equal [:primary, '/p'], [location(tree: 't', primary: '/p').source, location(tree: 't', primary: '/p').start_directory]
    assert_equal [:tree, '/work/t'], [location(tree: 't').source, location(tree: 't').start_directory]
    assert_equal [:home, Hiiro::TaskRecord.home_for('feat.x')], [location.source, location.start_directory]
  end

  def test_workspace_label
    assert_equal 'feat_x', location.workspace_label
    assert_equal 'my_sess', location(session: 'my.sess').workspace_label
  end

  def test_contains_uses_realpath_containment
    Dir.mktmpdir do |dir|
      real = File.realpath(dir)
      assert Hiiro::TaskLocation.contains?(dir, real)
      assert Hiiro::TaskLocation.contains?(dir, File.join(real, 'sub'))
      refute Hiiro::TaskLocation.contains?(dir, real + '-other')
      refute Hiiro::TaskLocation.contains?(File.join(dir, 'missing'), real)
      refute Hiiro::TaskLocation.contains?(nil, real)
    end
  end
end
