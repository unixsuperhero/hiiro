require "test_helper"
require "tmpdir"
require "fileutils"

class SaveTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("h-save")
    @orig_env = ENV["HIIRO_SAVED_DIR"]
    ENV["HIIRO_SAVED_DIR"] = @dir
    @harness = Hiiro::TestHarness.load_bin("bin/h-save")
  end

  def teardown
    ENV["HIIRO_SAVED_DIR"] = @orig_env
    FileUtils.rm_rf(@dir)
  end

  def test_registers_expected_subcommands
    %i[ls list dir show cat copy open edit rm remove].each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_slug_for_collapses_punctuation
    assert_equal "some-title-with-slashes", slug_for("  Some   Title: with/slashes ")
    assert_equal "text", slug_for("   ")
    assert_equal 32, slug_for("a" * 100).length
  end

  def test_save_text_writes_file_and_avoids_collisions
    first = save_text("hello world")
    second = save_text("hello world")

    assert File.exist?(first)
    assert File.exist?(second)
    refute_equal first, second
    assert_match(/-hello-world\.txt\z/, first)
    assert_match(/-hello-world-2\.txt\z/, second)
    assert_equal "hello world", File.read(first)
  end

  def test_saved_files_lists_newest_first
    save_text("aaa")
    File.write(File.join(@dir, "19990101000000-old.txt"), "old")

    assert_equal "19990101000000-old.txt", saved_files.last
    assert_equal 2, saved_files.size
  end
end
