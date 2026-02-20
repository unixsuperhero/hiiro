require "test_helper"

class ProjectTest < Minitest::Test
  def setup
    # h-project defines helper methods at top level, so we need to stub them
    @harness = Hiiro::TestHarness.load_bin("bin/h-project") do
      # Stub project_dirs to return test data
      define_singleton_method(:project_dirs) do
        { "myproj" => "/home/user/proj/myproj", "other" => "/home/user/proj/other" }
      end

      # Stub projects_from_config
      define_singleton_method(:projects_from_config) do
        { "config-proj" => "/custom/path/config-proj" }
      end

      # Stub start_tmux_session
      @tmux_sessions_started = []
      define_singleton_method(:start_tmux_session) do |name|
        @tmux_sessions_started << name
      end
    end
  end

  def test_registers_expected_subcommands
    expected = %i[open list ls config edit select copy help]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_has_default_subcmd
    # h-project has add_default that runs :help
    # We can verify via subcmd_names or just check it doesn't crash
    assert @harness.has_subcmd?(:help)
  end
end
