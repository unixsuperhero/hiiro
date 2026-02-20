require "test_helper"

class SessionTest < Minitest::Test
  def setup
    @mock_tmux = MockTmux.new
    mock = @mock_tmux  # capture for closure

    # Pass setup block to pre-configure stubs before bin's block runs
    @harness = Hiiro::TestHarness.load_bin("bin/h-session") do
      define_singleton_method(:tmux_client) { mock }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[ls list new kill attach rename switch detach has info open select copy]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_with_no_args_uses_tmux_client
    @mock_tmux.sessions = [MockSession.new("dev"), MockSession.new("work")]

    # Should iterate over sessions and puts each one
    # Since we can't easily capture puts, just verify no system call
    @harness.run_subcmd(:ls)

    assert_empty @harness.system_calls
  end

  def test_ls_with_args_calls_tmux_list_sessions
    @harness.run_subcmd(:ls, '-F', '#{session_name}')

    assert_equal [['tmux', 'list-sessions', '-F', '#{session_name}']], @harness.system_calls
  end

  def test_new_with_name_and_no_args_uses_tmux_client
    @harness.run_subcmd(:new, 'my-session')

    # With no extra args, should use tmux_client.new_session
    assert_empty @harness.system_calls
    assert_equal ['my-session'], @mock_tmux.new_session_calls
  end

  def test_new_with_extra_args_calls_system
    @harness.run_subcmd(:new, 'my-session', '-d')

    assert_equal [['tmux', 'new-session', 'my-session', '-d']], @harness.system_calls
  end

  def test_kill_with_name_and_no_args_uses_tmux_client
    @harness.run_subcmd(:kill, 'my-session')

    assert_empty @harness.system_calls
    assert_equal ['my-session'], @mock_tmux.kill_session_calls
  end

  def test_kill_with_extra_args_calls_system
    @harness.run_subcmd(:kill, 'my-session', '-a')

    assert_equal [['tmux', 'kill-session', '-t', 'my-session', '-a']], @harness.system_calls
  end

  def test_attach_with_name_and_no_args_uses_tmux_client
    @harness.run_subcmd(:attach, 'my-session')

    assert_empty @harness.system_calls
    assert_equal ['my-session'], @mock_tmux.attach_session_calls
  end

  def test_attach_with_extra_args_calls_system
    @harness.run_subcmd(:attach, 'my-session', '-r')

    assert_equal [['tmux', 'attach-session', '-t', 'my-session', '-r']], @harness.system_calls
  end

  def test_detach_with_no_args_uses_tmux_client
    @harness.run_subcmd(:detach)

    assert_empty @harness.system_calls
    assert @mock_tmux.detach_client_called
  end

  def test_detach_with_args_calls_system
    @harness.run_subcmd(:detach, '-a')

    assert_equal [['tmux', 'detach-client', '-a']], @harness.system_calls
  end

  # Mock classes for testing
  class MockTmux
    attr_accessor :sessions
    attr_reader :new_session_calls, :kill_session_calls, :attach_session_calls
    attr_reader :detach_client_called

    def initialize
      @sessions = []
      @new_session_calls = []
      @kill_session_calls = []
      @attach_session_calls = []
      @detach_client_called = false
    end

    def new_session(name, **opts)
      @new_session_calls << name
    end

    def kill_session(name)
      @kill_session_calls << name
    end

    def attach_session(name)
      @attach_session_calls << name
    end

    def detach_client
      @detach_client_called = true
    end

    def session_exists?(name)
      @sessions.any? { |s| s.name == name }
    end

    def open_session(name)
      # no-op for tests
    end

    def rename_session(old_name, new_name)
      # no-op for tests
    end

    def current_session
      @sessions.first
    end
  end

  class MockSession
    attr_reader :name, :windows

    def initialize(name, windows: 1, attached: false)
      @name = name
      @windows = windows
      @attached = attached
    end

    def attached?
      @attached
    end

    def to_s
      "#{name}: #{windows} windows"
    end
  end
end
