require "test_helper"

class LinkTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-link")
  end

  def test_registers_expected_subcommands
    expected = %i[add ls list search select copy editall edit open path]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_display_string_matches_the_numbered_ls_line
    entry = Hiiro::RegistryEntry.new(resource_type: "link", name: "jf", short_name: "jf",
                                     value: "http://x", description: "jellyfin")

    assert_equal "2. [jf] http://x - jellyfin", LinkPresenter.new(entry).display_string(1)
  end
end
