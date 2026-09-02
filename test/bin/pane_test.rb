require 'test_helper'

class PaneTest < Minitest::Test
  def setup
    @mock_herdr = MockHerdr.new
    mock = @mock_herdr
    @harness = Hiiro::TestHarness.load_bin('bin/h-pane') do
      define_singleton_method(:herdr_client) { mock }
    end
  end

  def test_registers_supported_herdr_subcommands
    expected = %i[ls lsa split splitv splith kill swap zoom capture select copy sw switch home move break join resize info]
    expected.each { |subcmd| assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd}" }
  end

  def test_ls_with_args_calls_herdr_pane_list
    @harness.run_subcmd(:ls, '--workspace', 'w1')
    assert_equal [['herdr', 'pane', 'list', '--workspace', 'w1']], @harness.system_calls
  end

  def test_split_calls_herdr_pane_split
    @harness.run_subcmd(:split, 'down', '--ratio', '0.4')
    assert_equal [['herdr', 'pane', 'split', '--current', '--direction', 'down', '--ratio', '0.4']], @harness.system_calls
  end

  def test_horizontal_and_vertical_splits_use_herdr_directions
    @harness.run_subcmd(:splith)
    @harness.run_subcmd(:splitv)
    assert_equal [:down, :right], @mock_herdr.split_directions
  end

  def test_kill_resolves_and_closes_pane
    @mock_herdr.panes_list = [MockPane.new('w1:p2', 'worker')]
    @harness.run_subcmd(:kill, 'worker')
    assert_equal ['w1:p2'], @mock_herdr.closed_panes
  end

  def test_capture_reads_current_pane
    with_env('HERDR_PANE_ID' => 'w1:p1') { @harness.run_subcmd(:capture) }
    assert_equal ['w1:p1'], @mock_herdr.read_panes
  end

  def test_resize_uses_native_direction_and_amount
    @harness.run_subcmd(:resize, 'right', '0.1', 'w1:p1')
    assert_equal [{ target: 'w1:p1', direction: 'right', amount: '0.1' }], @mock_herdr.resize_calls
  end

  private

  def with_env(values)
    old = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  class MockHerdr
    attr_accessor :panes_list
    attr_reader :closed_panes, :read_panes, :resize_calls, :split_directions

    def initialize
      @panes_list = []
      @closed_panes = []
      @read_panes = []
      @resize_calls = []
      @split_directions = []
    end

    def panes(**) = @panes_list
    def hsplit_window = @split_directions << :down
    def vsplit_window = @split_directions << :right
    def kill_pane(target) = @closed_panes << target
    def zoom_pane(*) = nil
    def swap_current_pane(*) = nil
    def swap_pane(*) = nil
    def focus_pane(*) = nil
    def break_pane(*) = nil
    def join_pane(*) = nil
    def current_pane = @panes_list.first
    def get_pane(target) = @panes_list.find { |pane| pane.id == target }
    def find_workspace(*) = nil
    def workspaces = []
    def tabs(**) = []

    def read_pane(target, **)
      @read_panes << target
      ''
    end

    def resize_pane(**options)
      @resize_calls << options
    end
  end

  MockPane = Data.define(:id, :name) do
    def to_s = name
  end
end
