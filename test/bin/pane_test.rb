require "test_helper"

class PaneTest < Minitest::Test
  def setup
    @mock_tmux = MockTmux.new
    mock = @mock_tmux

    @harness = Hiiro::TestHarness.load_bin("bin/h-pane") do
      define_singleton_method(:tmux_client) { mock }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[ls lsa split splitv splith kill swap zoom capture select copy sw switch move break join resize width height info]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_with_args_calls_tmux_list_panes
    @harness.run_subcmd(:ls, '-a')

    assert_equal [['tmux', 'list-panes', '-a']], @harness.system_calls
  end

  def test_lsa_with_args_calls_tmux_list_panes_all
    @harness.run_subcmd(:lsa, '-F', '#{pane_id}')

    assert_equal [['tmux', 'list-panes', '-a', '-F', '#{pane_id}']], @harness.system_calls
  end

  def test_split_calls_tmux_split_window
    @harness.run_subcmd(:split, '-h')

    assert_equal [['tmux', 'split-window', '-h']], @harness.system_calls
  end

  def test_splitv_with_args_calls_system
    @harness.run_subcmd(:splitv, '-l', '20')

    assert_equal [['tmux', 'split-window', '-v', '-l', '20']], @harness.system_calls
  end

  def test_splith_with_args_calls_system
    @harness.run_subcmd(:splith, '-l', '50%')

    assert_equal [['tmux', 'split-window', '-h', '-l', '50%']], @harness.system_calls
  end

  def test_kill_with_target_and_args_calls_system
    @harness.run_subcmd(:kill, '%5', '-a')

    assert_equal [['tmux', 'kill-pane', '-t', '%5', '-a']], @harness.system_calls
  end

  def test_swap_calls_tmux_swap_pane
    @harness.run_subcmd(:swap, '-D')

    assert_equal [['tmux', 'swap-pane', '-D']], @harness.system_calls
  end

  def test_zoom_with_args_calls_system
    @harness.run_subcmd(:zoom, '%5', '-Z')

    assert_equal [['tmux', 'resize-pane', '-Z', '-t', '%5', '-Z']], @harness.system_calls
  end

  def test_capture_with_args_calls_system
    @harness.run_subcmd(:capture, '-p', '-t', '%5')

    assert_equal [['tmux', 'capture-pane', '-p', '-t', '%5']], @harness.system_calls
  end

  def test_move_calls_tmux_move_pane
    @harness.run_subcmd(:move, '-t', 'other:')

    assert_equal [['tmux', 'move-pane', '-t', 'other:']], @harness.system_calls
  end

  def test_break_with_args_calls_system
    @harness.run_subcmd(:break, '-d')

    assert_equal [['tmux', 'break-pane', '-d']], @harness.system_calls
  end

  def test_join_calls_tmux_join_pane
    @harness.run_subcmd(:join, '-s', '%5')

    assert_equal [['tmux', 'join-pane', '-s', '%5']], @harness.system_calls
  end

  def test_resize_calls_tmux_resize_pane
    @harness.run_subcmd(:resize, '-x', '80')

    assert_equal [['tmux', 'resize-pane', '-x', '80']], @harness.system_calls
  end

  def test_width_with_target_calls_system
    @harness.run_subcmd(:width, '100', '%5')

    assert_equal [['tmux', 'resize-pane', '-x', '100', '-t', '%5']], @harness.system_calls
  end

  def test_height_with_target_calls_system
    @harness.run_subcmd(:height, '30', '%5')

    assert_equal [['tmux', 'resize-pane', '-y', '30', '-t', '%5']], @harness.system_calls
  end

  class MockTmux
    attr_accessor :panes_list

    def initialize
      @panes_list = []
    end

    def panes(all: false)
      @panes_list
    end

    def split_window(horizontal: true)
    end

    def kill_pane(target)
    end

    def resize_pane(target: nil, width: nil, height: nil, zoom: false)
    end

    def capture_pane
      ""
    end

    def break_pane
    end

    def open_session(target)
    end

    def current_pane
      @panes_list.first
    end
  end
end
