require "test_helper"

class WindowTest < Minitest::Test
  def setup
    @mock_tmux = MockTmux.new
    mock = @mock_tmux

    @harness = Hiiro::TestHarness.load_bin("bin/h-window") do
      define_singleton_method(:tmux_client) { mock }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[ls lsa new kill rename swap move select copy sw switch next prev last link unlink info]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_with_args_calls_tmux_list_windows
    @harness.run_subcmd(:ls, '-F', '#{window_name}')

    assert_equal [['tmux', 'list-windows', '-F', '#{window_name}']], @harness.system_calls
  end

  def test_lsa_with_args_calls_tmux_list_windows_all
    @harness.run_subcmd(:lsa, '-F', '#{window_name}')

    assert_equal [['tmux', 'list-windows', '-a', '-F', '#{window_name}']], @harness.system_calls
  end

  def test_new_with_extra_args_calls_system
    @harness.run_subcmd(:new, 'my-window', '-d')

    assert_equal [['tmux', 'new-window', '-n', 'my-window', '-d']], @harness.system_calls
  end

  def test_kill_with_target_and_args_calls_system
    @harness.run_subcmd(:kill, 'my-window', '-a')

    assert_equal [['tmux', 'kill-window', '-t', 'my-window', '-a']], @harness.system_calls
  end

  def test_rename_calls_tmux_rename_window
    @harness.run_subcmd(:rename, 'new-name')

    assert_equal [['tmux', 'rename-window', 'new-name']], @harness.system_calls
  end

  def test_swap_calls_tmux_swap_window
    @harness.run_subcmd(:swap, '-t', '1')

    assert_equal [['tmux', 'swap-window', '-t', '1']], @harness.system_calls
  end

  def test_move_calls_tmux_move_window
    @harness.run_subcmd(:move, '-t', 'other:')

    assert_equal [['tmux', 'move-window', '-t', 'other:']], @harness.system_calls
  end

  def test_next_with_args_calls_system
    @harness.run_subcmd(:next, '-a')

    assert_equal [['tmux', 'next-window', '-a']], @harness.system_calls
  end

  def test_prev_with_args_calls_system
    @harness.run_subcmd(:prev, '-a')

    assert_equal [['tmux', 'previous-window', '-a']], @harness.system_calls
  end

  def test_last_with_args_calls_system
    @harness.run_subcmd(:last, '-t', 'session')

    assert_equal [['tmux', 'last-window', '-t', 'session']], @harness.system_calls
  end

  def test_link_calls_tmux_link_window
    @harness.run_subcmd(:link, '-s', 'src', '-t', 'dst')

    assert_equal [['tmux', 'link-window', '-s', 'src', '-t', 'dst']], @harness.system_calls
  end

  def test_unlink_with_args_calls_system
    @harness.run_subcmd(:unlink, 'my-window', '-k')

    assert_equal [['tmux', 'unlink-window', '-t', 'my-window', '-k']], @harness.system_calls
  end

  class MockTmux
    attr_accessor :windows_list

    def initialize
      @windows_list = []
    end

    def windows(all: false)
      @windows_list
    end

    def new_window(name: nil)
    end

    def kill_window(target)
    end

    def next_window
    end

    def previous_window
    end

    def last_window
    end

    def unlink_window(target)
    end

    def open_session(target)
    end

    def current_window
      @windows_list.first
    end
  end
end
