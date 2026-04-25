require "test_helper"
require_relative "../../plugins/pins"

class ClaudeTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @claude_dir = File.join(@test_dir, ".claude")
    FileUtils.mkdir_p(File.join(@claude_dir, "agents"))
    FileUtils.mkdir_p(File.join(@claude_dir, "commands"))
    FileUtils.mkdir_p(File.join(@claude_dir, "skills", "review"))
    File.write(File.join(@claude_dir, "agents", "fetch.md"), "# fetch\n")
    File.write(File.join(@claude_dir, "commands", "refactor.md"), "# refactor\n")
    File.write(File.join(@claude_dir, "skills", "review", "SKILL.md"), "# review\n")

    claude_path = Pathname(@claude_dir)

    @harness = Hiiro::TestHarness.load_bin("bin/h-claude") do
      define_singleton_method(:claude_paths) { [claude_path] }
      define_singleton_method(:edit_files) { |*paths| @edited_files = paths }
      define_singleton_method(:edited_files) { @edited_files }
    end
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def test_agents_absolute_prints_markdown_path
    out, err = capture_io { @harness.run_subcmd(:agents, "-a", "fetch") }

    assert_equal "#{File.join(@claude_dir, 'agents', 'fetch.md')}\n", out
    assert_equal "", err
  end

  def test_skills_absolute_prints_skill_markdown_path
    out, err = capture_io { @harness.run_subcmd(:skills, "-a", "review") }

    assert_equal "#{File.join(@claude_dir, 'skills', 'review', 'SKILL.md')}\n", out
    assert_equal "", err
  end

  def test_vim_accepts_absolute_flag_from_shared_tool_opts
    @harness.run_subcmd(:vim, "-a", "fetch", "review")

    assert_equal [
      File.join(@claude_dir, "agents", "fetch.md"),
      File.join(@claude_dir, "skills", "review", "SKILL.md"),
    ], @harness.edited_files
  end
end
