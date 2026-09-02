require 'test_helper'

class WindowTest < Minitest::Test
  def setup
    @mock_herdr = MockHerdr.new
    mock = @mock_herdr
    @harness = Hiiro::TestHarness.load_bin('bin/h-window') do
      define_singleton_method(:herdr_client) { mock }
    end
  end

  def test_registers_supported_herdr_tab_subcommands
    expected = %i[ls lsa new kill rename select copy sw switch next prev last info]
    expected.each { |subcmd| assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd}" }
  end

  def test_ls_with_args_calls_herdr_tab_list
    @harness.run_subcmd(:ls, '--workspace', 'w1')
    assert_equal [['herdr', 'tab', 'list', '--workspace', 'w1']], @harness.system_calls
  end

  def test_new_creates_focused_tab
    @harness.run_subcmd(:new, 'tests', '/code')
    assert_equal [{ name: 'tests', start_directory: '/code', focus: true }], @mock_herdr.new_tab_calls
  end

  def test_kill_resolves_and_closes_tab
    @mock_herdr.tabs_list = [MockTab.new('w1:t2', 'tests')]
    @harness.run_subcmd(:kill, 'tests')
    assert_equal ['w1:t2'], @mock_herdr.closed_tabs
  end

  def test_switch_focuses_tab
    @mock_herdr.tabs_list = [MockTab.new('w1:t2', 'tests')]
    @harness.run_subcmd(:switch, 'tests')
    assert_equal ['w1:t2'], @mock_herdr.focused_tabs
  end

  class MockHerdr
    attr_accessor :tabs_list
    attr_reader :new_tab_calls, :closed_tabs, :focused_tabs

    def initialize
      @tabs_list = []
      @new_tab_calls = []
      @closed_tabs = []
      @focused_tabs = []
    end

    def tabs(**) = @tabs_list
    def new_tab(**options) = @new_tab_calls << options
    def close_tab(target) = @closed_tabs << target
    def focus_tab(target) = @focused_tabs << target
    def rename_tab(*) = nil
    def current_tab = @tabs_list.first
    def find_tab(target) = @tabs_list.find { |tab| [tab.id, tab.name].include?(target) }
    def next_tab = nil
    def previous_tab = nil
    def last_tab = nil
    def panes(**) = []
    def workspaces = []
  end

  MockTab = Data.define(:id, :name) do
    def to_s = name
  end
end
