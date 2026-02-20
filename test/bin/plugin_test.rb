require "test_helper"

class PluginTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @test_dir = Dir.mktmpdir
    test_dir = @test_dir

    @harness = Hiiro::TestHarness.load_bin("bin/h-plugin") do
      define_singleton_method(:tmux_client) { MockTmux.new }
      define_singleton_method(:get_value) { |key| test_dir }
      define_singleton_method(:plugin_files) { ["#{test_dir}/pins.rb", "#{test_dir}/tasks.rb"] }
    end
  end

  def teardown
    Dir.chdir(@original_dir) if @original_dir
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def test_registers_expected_subcommands
    expected = %i[path ls edit rg rgall]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_rg_calls_ripgrep_with_smart_case
    @harness.run_subcmd(:rg, 'pattern')

    assert_equal [['rg', '-S', 'pattern']], @harness.system_calls
  end

  def test_rg_passes_extra_args
    @harness.run_subcmd(:rg, '-i', 'pattern', '-A', '3')

    assert_equal [['rg', '-S', '-i', 'pattern', '-A', '3']], @harness.system_calls
  end

  def test_rgall_calls_ripgrep_with_no_ignore
    @harness.run_subcmd(:rgall, 'pattern')

    assert_equal [['rg', '-S', '--no-ignore-vcs', 'pattern']], @harness.system_calls
  end

  def test_edit_without_args_opens_self
    @harness.run_subcmd(:edit)

    assert_equal 1, @harness.system_calls.size
    call = @harness.system_calls.first
    assert_includes call.last, 'h-plugin'
  end

  class MockTmux
    def sessions
      []
    end
  end
end
