require "test_helper"

class TableBinTest < Minitest::Test
  def setup
    clear_rows
    @harness = Hiiro::TestHarness.load_bin("bin/h-table")
    @task = Hiiro::TaskRecord.create(name: "alpha")
    Hiiro::Table.named("link").add("gh", value: "github.com")
    Hiiro::Table.named("link").add("hn", value: "news.com", task_id: @task.id)
    Hiiro::Table.named("sound").add("ping", value: "Ping.aiff")
  end

  def teardown = clear_rows

  def clear_rows
    [Hiiro::RegistryEntry, Hiiro::Tag, Hiiro::TaskRecord].each { |model| model.dataset.delete }
  end

  def run_cli(*args)
    capture_io { @harness.run_subcmd(*args) }
  end

  # Exits with 1; returns [stdout, stderr].
  def run_failing(*args)
    out, err = capture_io { assert_raises(SystemExit) { @harness.run_subcmd(*args) } }
    [out, err]
  end

  def with_current_task(task)
    original = Hiiro::TableScope.method(:resolve)
    Hiiro::TableScope.define_singleton_method(:resolve) { |**| task }
    yield
  ensure
    Hiiro::TableScope.define_singleton_method(:resolve, original)
  end

  def entry(name) = Hiiro::RegistryEntry.first(name:)

  def test_registers_every_subcommand
    %i[ui tables ls list add rm remove mv set get tag untag].each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_tables_prints_name_and_count
    assert_equal ["link  2\nsound  1\n", ""], run_cli(:tables)
  end

  def test_ls_global_prints_tab_separated_rows
    assert_equal ["link\tgh\tgithub.com\nlink\thn\tnews.com\nsound\tping\tPing.aiff\n", ""], run_cli(:ls, "-g")
    assert_equal ["sound\tping\tPing.aiff\n", ""], run_cli(:ls, "--global", "sound")
    assert_equal ["No entries.\n", ""], run_cli(:ls, "-g", "missing")
  end

  def test_ls_defaults_to_the_current_task_scope
    with_current_task(@task) do
      assert_equal ["link\thn\tnews.com\n", ""], run_cli(:ls)
    end
    with_current_task(nil) do
      assert_equal "sound\tping\tPing.aiff\n", run_cli(:ls, "sound").first
    end
  end

  def test_add_creates_an_entry
    assert_equal ["added dir/src\n", ""], run_cli(:add, "dir", "src", "~/src", "-s", "s", "-d", "sources")

    assert_equal ["dir", "~/src", "s", "sources", nil],
      [:resource_type, :value, :short_name, :description, :task_id].map { |field| entry("src").send(field) }
  end

  def test_add_with_task_flag_attaches_the_current_task
    with_current_task(@task) do
      assert_equal ["added dir/w\n", ""], run_cli(:add, "dir", "w", "~/w", "--task")
    end

    assert_equal @task.id, entry("w").task_id
  end

  def test_add_with_task_flag_and_no_task_fails
    with_current_task(nil) do
      assert_equal ["", "No current task.\n"], run_failing(:add, "dir", "w", "~/w", "--task")
    end

    assert_nil entry("w")
  end

  def test_add_duplicate_fails
    assert_equal ["", "exists: link/gh\n"], run_failing(:add, "link", "gh", "other")
    assert_equal "github.com", entry("gh").value
  end

  def test_get_prints_the_value
    assert_equal ["github.com\n", ""], run_cli(:get, "link", "gh")
    assert_equal ["", "not found: link/nope\n"], run_failing(:get, "link", "nope")
  end

  def test_set_updates_the_value
    assert_equal ["set link/gh\n", ""], run_cli(:set, "link", "gh", "gitlab.com")
    assert_equal "gitlab.com", entry("gh").value
  end

  def test_tag_and_untag_print_the_resulting_tags
    assert_equal ["tags link/gh: a b\n", ""], run_cli(:tag, "link", "gh", "b", "a")
    assert_equal ["tags link/gh: b\n", ""], run_cli(:untag, "link", "gh", "a")
  end

  def test_rm_deletes_the_entry_and_its_tags
    entry("gh").tag("x")

    assert_equal ["removed link/gh\n", ""], run_cli(:rm, "link", "gh")
    assert_nil entry("gh")
    assert_equal 0, Hiiro::Tag.count
    assert_equal ["", "not found: link/gh\n"], run_failing(:rm, "link", "gh")
  end

  def test_mv_renames_a_table
    assert_equal ["renamed link to web\n", ""], run_cli(:mv, "link", "web")
    assert_equal %w[sound web], Hiiro::Table.all.map(&:name)
    assert_equal ["", "table already exists: web\n"], run_failing(:mv, "sound", "web")
  end
end
