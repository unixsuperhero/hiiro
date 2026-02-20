require "test_helper"

class LinkTest < Minitest::Test
  def setup
    @mock_lm = MockLinkManager.new
    mock = @mock_lm

    @harness = Hiiro::TestHarness.load_bin("bin/h-link") do
      define_singleton_method(:tmux_client) { MockTmux.new }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[add ls list search select copy editall edit open path]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  class MockLinkManager
    def load_links
      []
    end

    def save_links(links)
    end

    def links_file
      "/tmp/test_links.yml"
    end

    def load_link_hash(links = nil)
      {}
    end

    def hash_matches?(lines, *args)
      lines
    end

    def has_placeholders?(url)
      false
    end
  end

  class MockTmux
    def sessions
      []
    end
  end
end
