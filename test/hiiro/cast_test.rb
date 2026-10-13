require "test_helper"
require "tmpdir"

class CastTest < Minitest::Test
  DAY = Date.new(2026, 10, 13)

  def setup
    @dir = Dir.mktmpdir("casts")
    @casts = Hiiro::Cast.new(dir: @dir, editor: ["safe_nvim"], resume_args: ['+norm! g`"'])
  end

  def teardown = FileUtils.rm_rf(@dir)

  def touch(name) = File.write(File.join(@dir, name), "")
  def path(name) = File.join(@dir, name)

  def test_empty_day_names
    assert_equal path("20261013000.cast"), @casts.path(:next, day: DAY)
    assert_equal path("20261013000.cast"), @casts.path(:current, day: DAY)
    assert_equal path("20261013000.cast"), @casts.path(:previous, day: DAY)
  end

  def test_kinds_follow_the_highest_index_of_that_day_only
    %w[20261013000.cast 20261013001.cast 20261013004.cast 20261012009.cast 20261013x.cast 2026101300.cast].each { |n| touch(n) }
    assert_equal path("20261013005.cast"), @casts.path(:next, day: DAY)
    assert_equal path("20261013004.cast"), @casts.path(:current, day: DAY)
    assert_equal path("20261013004.cast"), @casts.path(:last, day: DAY)
    assert_equal path("20261013003.cast"), @casts.path(:previous, day: DAY)
    assert_equal path("20261013000.cast"), @casts.path(:first, day: DAY)
    assert_equal path("20261012010.cast"), @casts.path(:next, day: DAY - 1)
    assert_equal path("20261013012.cast"), @casts.path(12, day: DAY)
  end

  def test_day_parsing
    assert_equal Date.new(2026, 10, 6), Hiiro::Cast.day("-7", today: DAY)
    assert_equal Date.new(2026, 10, 14), Hiiro::Cast.day("+1", today: DAY)
    assert_equal Date.new(2025, 1, 2), Hiiro::Cast.day("20250102", today: DAY)
    error = assert_raises(Hiiro::Error) { Hiiro::Cast.day("2025-01-02") }
    assert_equal 'invalid day: "2025-01-02" (use a relative day like -7 or YYYYMMDD)', error.message
    assert_equal 7, Hiiro::Cast.index("007")
    assert_equal 'invalid index: "-1"', assert_raises(Hiiro::Error) { Hiiro::Cast.index("-1") }.message
    assert_equal 'invalid index: "x"', assert_raises(Hiiro::Error) { Hiiro::Cast.index("x") }.message
  end

  def test_editor_recipes_quote_arguments_for_the_recorded_shell
    assert_equal "safe_nvim notes.md my\\ file.md", @casts.record_command(["notes.md", "my file.md"])
    assert_equal %q{safe_nvim +norm\!\ g\`\" notes.md}, @casts.resume_command(["notes.md"])
  end

  def test_profile_section_supplies_dir_editor_and_resume_args
    profile = Hiiro::Profile.new({ "casts" => { "dir" => "~/notes/yt/casts", "editor" => "safe_nvim -u x", "resume_args" => ["+5"] } })
    casts = Hiiro::Cast.from_profile(profile)
    assert_equal File.expand_path("~/notes/yt/casts"), casts.dir
    assert_equal %w[safe_nvim -u x], casts.editor
    assert_equal "safe_nvim -u x +5 a", casts.resume_command(["a"])
    defaults = Hiiro::Cast.from_profile(Hiiro::Profile.new({}))
    assert_equal File.expand_path("~/casts"), defaults.dir
    assert_equal ['+norm! g`"'], defaults.resume_args
  end
end
