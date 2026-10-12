require "test_helper"
require "open3"

class ProjectCatalogTest < Minitest::Test
  GIT_ENV = {
    "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
    "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@t", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@t",
    "GIT_AUTHOR_DATE" => "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2026-01-01T00:00:00Z",
  }.freeze
  HEAD = "8f97e39".freeze

  def setup
    @saved_env = ENV.to_h.slice(*GIT_ENV.keys)
    ENV.update(GIT_ENV)
    @tmp = Dir.mktmpdir("projroot")
    @root = File.realpath(@tmp)
    @alpha = File.join(@root, "alpha")
    repo(@alpha)
    git(@alpha, "worktree", "add", "-q", "../alpha-feat", "-b", "feat")
    Dir.mkdir(File.join(@root, "notes"))
    Dir.mkdir(File.join(@root, "zeta"))
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    GIT_ENV.each_key { |key| ENV.delete(key) }
    ENV.update(@saved_env)
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def repo(dir)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    git(dir, "init", "-q", "-b", "main")
    File.write(File.join(dir, "README"), "x\n")
    git(dir, "add", ".")
    git(dir, "commit", "-q", "-m", "init")
  end

  def catalog(roots: [@root], aliases: { "site" => "/tmp/x" })
    Hiiro::ProjectCatalog.load(roots:, aliases:)
  end

  def test_rows_group_worktrees_under_their_repo_and_interleave_dirs_and_aliases_by_name
    rows = catalog.rows

    assert_equal ["alpha", "alpha ▸ alpha-feat", "notes", "site", "zeta"], rows.map(&:name)
    assert_equal %i[tree tree dir alias dir], rows.map(&:kind)
    assert_equal ["main", "feat", nil, nil, nil], rows.map(&:branch)
    assert_equal [HEAD, HEAD, nil, nil, nil], rows.map(&:head)
    assert_equal [@alpha, File.join(@root, "alpha-feat"), File.join(@root, "notes"), "/tmp/x", File.join(@root, "zeta")], rows.map(&:path)
    assert_equal [true, false, false, false, false], rows.map(&:main?)
  end

  def test_an_extra_worktree_directory_is_not_a_separate_repo
    cat = catalog

    assert_equal [@alpha], cat.repos.keys
    assert_equal ["alpha", @alpha], [cat.repos[@alpha].name, cat.repos[@alpha].path]
    assert_equal [@alpha, File.join(@root, "alpha-feat")], cat.repos[@alpha].trees.map(&:path)
    assert_same cat.repos[@alpha], cat.repo_for(cat.rows[1])
    assert_nil cat.repo_for(cat.rows[2])
  end

  def test_a_root_that_is_itself_a_repo_is_one_repo_named_after_the_root
    Dir.mktmpdir("rootrepo") do |tmp|
      root = File.realpath(tmp)
      repo(root)
      git(root, "worktree", "add", "-q", "sub", "-b", "sub")
      name = File.basename(root)
      rows = catalog(roots: [root], aliases: {}).rows

      assert_equal [name, "#{name} ▸ sub"], rows.map(&:name)
      assert_equal [root, File.join(root, "sub")], rows.map(&:path)
      assert_equal %w[main sub], rows.map(&:branch)
      assert_equal [true, false], rows.map(&:main?)
    end
  end

  def test_missing_roots_are_skipped_and_reload_rereads_the_disk
    cat = catalog(roots: [@root, File.join(@root, "missing")], aliases: {})

    assert_equal 4, cat.rows.length

    Dir.mkdir(File.join(@root, "beta"))
    cat.reload

    assert_equal ["alpha", "alpha ▸ alpha-feat", "beta", "notes", "zeta"], cat.rows.map(&:name)
  end
end
