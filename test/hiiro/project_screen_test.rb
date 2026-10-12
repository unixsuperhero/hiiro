require "test_helper"
require "open3"

class ProjectScreenTest < Minitest::Test
  GIT_ENV = {
    "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
    "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@t", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@t",
    "GIT_AUTHOR_DATE" => "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2026-01-01T00:00:00Z",
  }.freeze
  TUIOS_KEYS = %w[TUIOS_ENV TUIOS_SESSION].freeze
  HEADER = "projects  scope:global  5 rows".freeze
  HINT = "[enter]open [/]search [g]scope [s]tatus [b]ranches [p]rs [a]dd tree [d]rop tree [y]ank pa…".freeze
  BLANK = " " * 44
  ALPHA = "  alpha               main  8f97e39         │".freeze
  FEAT = "  alpha ▸ alpha-feat  feat  8f97e39         │".freeze
  NOTES = "  notes               -                     │".freeze
  SITE = "  site                -                     │".freeze
  ZETA = "  zeta                -                     │".freeze

  class FakeFetcher
    attr_reader :calls

    def initialize = @calls = []

    def status(path)
      @calls << [:status, path]
      { dirty: 1, ahead: 0, behind: 0 }
    end

    def branches(repo_path)
      @calls << [:branches, repo_path]
      %w[feat main]
    end

    def prs(repo_path)
      @calls << [:prs, repo_path]
      [{ number: 7, state: "OPEN", title: "Add ui" }]
    end
  end

  class FakeOpener
    attr_reader :rows

    def initialize = @rows = []

    def open(row) = @rows << row
  end

  def setup
    @saved_env = ENV.to_h.slice(*GIT_ENV.keys, *TUIOS_KEYS)
    ENV.update(GIT_ENV)
    TUIOS_KEYS.each { |key| ENV.delete(key) }
    Hiiro::TaskRecord.dataset.delete
    @tmp = Dir.mktmpdir("projroot")
    @root = File.realpath(@tmp)
    @alpha = File.join(@root, "alpha")
    @feat = File.join(@root, "alpha-feat")
    repo(@alpha)
    git(@alpha, "worktree", "add", "-q", "../alpha-feat", "-b", "feat")
    Dir.mkdir(File.join(@root, "notes"))
    Dir.mkdir(File.join(@root, "zeta"))
    @catalog = Hiiro::ProjectCatalog.load(roots: [@root], aliases: { "site" => "/tmp/x" })
    @fetcher = FakeFetcher.new
    @opener = FakeOpener.new
    @copied = []
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    Hiiro::TaskRecord.dataset.delete
    (GIT_ENV.keys + TUIOS_KEYS).each { |key| ENV.delete(key) }
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

  def screen_for(**kw)
    Hiiro::ProjectScreen.new(catalog: @catalog, fetcher: @fetcher, opener: @opener, clipboard: ->(text) { @copied << text }, **kw)
  end

  def press(screen, *keys) = keys.each { |key| screen.handle_key(key) }

  def type(screen, text) = press(screen, *text.chars, :enter)

  def frame(screen) = screen.frame(rows: 14, cols: 90)

  # The detail pane is 45 columns wide; the tmpdir path is longer than that.
  def right(text) = text.length > 45 ? "#{text[0, 44]}…" : text

  def path_line(path) = right("path     #{path}")

  def footer(text) = text.length > 90 ? "#{text[0, 89]}…" : text

  def test_initial_list_shows_one_row_per_worktree_dir_and_alias_with_the_tree_detail
    assert_equal [
      HEADER,
      HINT,
      "> alpha               main  8f97e39         │name     alpha",
      "#{FEAT}#{path_line(@alpha)}",
      "#{NOTES}repo     alpha",
      "#{SITE}branch   main",
      "#{ZETA}head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   -",
      "#{BLANK}│branches -",
      "#{BLANK}│prs      -",
      "1/5",
    ], frame(screen_for)
  end

  def test_dir_and_alias_rows_show_name_path_and_kind_only
    screen = screen_for
    press(screen, "j", "j", "j")

    assert_equal [
      "#{ALPHA}name     site",
      "#{FEAT}path     /tmp/x",
      "#{NOTES}kind     alias",
      "> site                -                     │",
    ], frame(screen)[2, 4]
  end

  def test_search_matches_the_branch_name
    screen = screen_for
    type(screen, "/feat")

    assert_equal [
      HEADER,
      HINT,
      "> alpha ▸ alpha-feat  feat  8f97e39         │name     alpha ▸ alpha-feat",
      "#{BLANK}│#{path_line(@feat)}",
      "#{BLANK}│repo     alpha",
      "#{BLANK}│branch   feat",
      "#{BLANK}│head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   -",
      "#{BLANK}│branches -",
      "#{BLANK}│prs      -",
      "/feat  1/1",
    ], frame(screen)
  end

  def test_s_fetches_status_for_the_tree_and_marks_the_row
    screen = screen_for
    press(screen, "s")

    assert_equal [[:status, @alpha]], @fetcher.calls
    assert_equal [
      HEADER,
      HINT,
      "> alpha               main *1  8f97e39      │name     alpha",
      "#{FEAT}#{path_line(@alpha)}",
      "#{NOTES}repo     alpha",
      "#{SITE}branch   main",
      "#{ZETA}head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   *1",
      "#{BLANK}│branches -",
      "#{BLANK}│prs      -",
      "1/5",
    ], frame(screen)
  end

  def test_real_fetcher_reads_status_and_branches_from_git
    File.write(File.join(@alpha, "dirty.txt"), "x")
    fetcher = Hiiro::ProjectScreen::Fetcher.new

    assert_equal({ dirty: 1, ahead: 0, behind: 0 }, fetcher.status(@alpha))
    assert_equal %w[feat main], fetcher.branches(@alpha)
    assert_raises(Hiiro::Error) { fetcher.status(File.join(@root, "notes")) }
  end

  def test_b_lists_the_repo_branches_in_the_pane
    screen = screen_for
    press(screen, "b")

    assert_equal [[:branches, @alpha]], @fetcher.calls
    assert_equal [
      HEADER,
      HINT,
      "> alpha               main  8f97e39         │name     alpha",
      "#{FEAT}#{path_line(@alpha)}",
      "#{NOTES}repo     alpha",
      "#{SITE}branch   main",
      "#{ZETA}head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   -",
      "#{BLANK}│branches (2)",
      "#{BLANK}│  feat",
      "1/5",
    ], frame(screen)
  end

  def test_p_lists_the_repo_prs_in_the_pane
    screen = screen_for
    press(screen, "j", "p")

    assert_equal [[:prs, @alpha]], @fetcher.calls
    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA}name     alpha ▸ alpha-feat",
      "> alpha ▸ alpha-feat  feat  8f97e39         │#{path_line(@feat)}",
      "#{NOTES}repo     alpha",
      "#{SITE}branch   feat",
      "#{ZETA}head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   -",
      "#{BLANK}│branches -",
      "#{BLANK}│prs (1)",
      "2/5",
    ], frame(screen)
    assert_equal "  #7  OPEN  Add ui", screen.detail_lines(screen.current_item).last
  end

  def test_fetch_errors_become_the_status_message
    fetcher = Object.new
    def fetcher.prs(_path) = raise(Hiiro::Error, "gh: not logged in")
    screen = screen_for(fetcher:)
    press(screen, "p")

    assert_equal "gh: not logged in  1/5", frame(screen).last

    press(screen, "j", "j", "s")

    assert_equal "not a git worktree  3/5", frame(screen).last
  end

  def test_g_scopes_to_the_current_task_repo_with_the_cursor_on_its_tree
    task = Hiiro::TaskRecord.create_task("tcli")
    task.update(tree: @feat)
    screen = screen_for(current: task)
    press(screen, "g")

    assert_equal [
      "projects  scope:task(@tcli)  2 rows",
      HINT,
      "#{ALPHA}name     alpha ▸ alpha-feat",
      "> alpha ▸ alpha-feat  feat  8f97e39         │#{path_line(@feat)}",
      "#{BLANK}│repo     alpha",
      "#{BLANK}│branch   feat",
      "#{BLANK}│head     8f97e39",
      "#{BLANK}│worktrees (2)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│status   -",
      "#{BLANK}│branches -",
      "#{BLANK}│prs      -",
      "2/2",
    ], frame(screen)

    press(screen, "g")

    assert_equal HEADER, frame(screen)[0]
    assert_equal "2/5", frame(screen).last
  end

  def test_g_without_a_current_task_in_the_catalog_reports_it
    screen = screen_for
    press(screen, "g")

    assert_equal "no current task to scope to  1/5", frame(screen).last

    task = Hiiro::TaskRecord.create_task("elsewhere")
    task.update(tree: "/nowhere")

    assert_equal :global, screen_for(current: task, scope: :task).scope
  end

  def test_a_creates_the_worktree_on_disk_and_selects_its_row
    screen = screen_for
    press(screen, "a")

    assert_equal "branch: _", frame(screen).last

    type(screen, "new1")

    assert_equal footer("path: #{File.join(@root, 'new1')}_"), frame(screen).last

    press(screen, :enter)
    new1 = File.join(@root, "new1")

    assert_equal [
      "projects  scope:global  6 rows",
      HINT,
      "#{ALPHA}name     alpha ▸ new1",
      "#{FEAT}#{path_line(new1)}",
      "> alpha ▸ new1        new1  8f97e39         │repo     alpha",
      "#{NOTES}branch   new1",
      "#{SITE}head     8f97e39",
      "#{ZETA}worktrees (3)",
      "#{BLANK}│  alpha  main",
      "#{BLANK}│  alpha-feat  feat",
      "#{BLANK}│  new1  new1",
      "#{BLANK}│status   -",
      "#{BLANK}│branches -",
      footer("added #{new1}  3/6"),
    ], frame(screen)
    assert_includes git(@alpha, "worktree", "list"), new1
    assert_includes git(@alpha, "branch", "--format=%(refname:short)").split, "new1"

    press(screen, "d")

    assert_equal footer("remove #{new1}? (y/n): _"), frame(screen).last

    type(screen, "y")

    assert_equal [
      HEADER,
      HINT,
      "#{ALPHA}name     notes",
      "#{FEAT}#{path_line(File.join(@root, 'notes'))}",
      "> notes               -                     │kind     dir",
    ], frame(screen)[0, 5]
    assert_equal footer("removed #{new1}  3/5"), frame(screen).last
    refute Dir.exist?(new1)
    refute_includes git(@alpha, "worktree", "list"), new1
  end

  def test_a_with_an_empty_branch_cancels
    screen = screen_for
    press(screen, "a", :enter)

    assert_equal "1/5", frame(screen).last
    assert_equal 5, @catalog.rows.length
  end

  def test_d_refuses_the_main_tree_dirs_and_aliases
    screen = screen_for
    press(screen, "d")

    assert_equal "not a removable worktree  1/5", frame(screen).last

    press(screen, "j", "j", "d")

    assert_equal "not a removable worktree  3/5", frame(screen).last
    assert Dir.exist?(@alpha)
  end

  def test_d_on_an_extra_tree_with_anything_but_y_changes_nothing
    screen = screen_for
    press(screen, "j", "d")
    type(screen, "n")

    assert Dir.exist?(@feat)
    assert_equal "2/5", frame(screen).last
  end

  def test_y_copies_the_row_path
    screen = screen_for
    press(screen, "j", "y")

    assert_equal [@feat], @copied
    assert_equal footer("copied #{@feat}  2/5"), frame(screen).last
  end

  def test_enter_opens_the_row_and_finishes_the_screen
    screen = screen_for
    press(screen, "j")

    assert_equal true, screen.handle_key(:enter)
    assert_equal [@feat], @opener.rows.map(&:path)
  end

  def test_opener_errors_keep_the_screen_open
    opener = Object.new
    def opener.open(_row) = raise(Hiiro::Error, "tuios new-window failed")
    screen = screen_for(opener:)

    assert_equal :continue, screen.handle_key("o")
    assert_equal "tuios new-window failed  1/5", frame(screen).last
  end

  def test_opener_command_is_tuios_new_window_inside_tuios_and_nil_otherwise
    opener = Hiiro::ProjectScreen::Opener.new
    row = @catalog.rows.first

    assert_nil opener.command(row)

    ENV["TUIOS_ENV"] = "1"
    ENV["TUIOS_SESSION"] = "sess"

    assert_equal ["tuios", "new-window", "alpha", "-s", "sess", "--cwd", @alpha], opener.command(row)
    assert_equal ["tuios", "new-window", "alpha_alpha-feat", "-s", "sess", "--cwd", @feat], opener.command(@catalog.rows[1])
  end
end
