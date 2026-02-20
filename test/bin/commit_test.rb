require "test_helper"

class CommitTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-commit")
  end

  def test_registers_expected_subcommands
    expected = %i[edit select sk]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_edit_opens_editor_on_self
    @harness.run_subcmd(:edit)

    assert_equal 1, @harness.system_calls.size
    # Should call editor with the file path
    call = @harness.system_calls.first
    assert_includes call.last, 'h-commit'
  end

  def test_sk_is_alias_for_select
    assert @harness.has_subcmd?(:sk)
    assert @harness.has_subcmd?(:select)
  end
end
