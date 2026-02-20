require "test_helper"

class ConfigTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-config") do
      # Stub open_config to capture calls instead of actually opening editor
      @open_config_calls = []
      define_singleton_method(:open_config) do |dir:, file:|
        @open_config_calls << { dir: dir, file: file }
      end

      # Stub make_child for nested subcommands
      define_singleton_method(:make_child) do |subcmd, *args, &block|
        # Just return self for testing - nested subcommands tested separately
        self
      end
    end
  end

  def test_registers_expected_subcommands
    expected = %i[vim git tmux zsh profile starship claude]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_tmux_opens_tmux_conf
    @harness.run_subcmd(:tmux)

    calls = @harness.instance_variable_get(:@open_config_calls)
    assert_equal 1, calls.size
    assert_equal '~', calls.first[:dir]
    assert_equal '.tmux.conf', calls.first[:file]
  end

  def test_zsh_opens_zshrc
    @harness.run_subcmd(:zsh)

    calls = @harness.instance_variable_get(:@open_config_calls)
    assert_equal 1, calls.size
    assert_equal '~', calls.first[:dir]
    assert_equal '.zshrc', calls.first[:file]
  end

  def test_profile_opens_zprofile
    @harness.run_subcmd(:profile)

    calls = @harness.instance_variable_get(:@open_config_calls)
    assert_equal 1, calls.size
    assert_equal '~', calls.first[:dir]
    assert_equal '.zprofile', calls.first[:file]
  end

  def test_starship_opens_starship_toml
    @harness.run_subcmd(:starship)

    calls = @harness.instance_variable_get(:@open_config_calls)
    assert_equal 1, calls.size
    assert_equal '~/.config/starship', calls.first[:dir]
    assert_equal 'starship.toml', calls.first[:file]
  end

  def test_claude_opens_settings_json
    @harness.run_subcmd(:claude)

    calls = @harness.instance_variable_get(:@open_config_calls)
    assert_equal 1, calls.size
    assert_equal '~/.claude', calls.first[:dir]
    assert_equal 'settings.json', calls.first[:file]
  end
end
