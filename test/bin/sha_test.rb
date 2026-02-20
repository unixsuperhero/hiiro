require "test_helper"

class ShaTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-sha")
  end

  def test_registers_expected_subcommands
    expected = %i[select ls show copy]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_calls_git_log_oneline
    @harness.run_subcmd(:ls)

    assert_equal [['git', 'log', '--oneline']], @harness.system_calls
  end

  def test_ls_passes_extra_args
    @harness.run_subcmd(:ls, '-10', '--all')

    assert_equal [['git', 'log', '--oneline', '-10', '--all']], @harness.system_calls
  end

  def test_show_with_sha_calls_git_show
    @harness.run_subcmd(:show, 'abc123')

    assert_equal [['git', 'show', 'abc123']], @harness.system_calls
  end

  def test_show_with_sha_and_args
    @harness.run_subcmd(:show, 'abc123', '--stat')

    assert_equal [['git', 'show', 'abc123', '--stat']], @harness.system_calls
  end
end
