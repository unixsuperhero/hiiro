require 'test_helper'

class TmuxEffectsTest < Minitest::Test
  def setup
    @executor = Hiiro::Effects::NullExecutor.new
    @tmux = Hiiro::Tmux.new(executor: @executor)
  end

  def test_new_window_calls_run
    @tmux.new_window(name: 'main', target: 'mysession')
    assert @executor.called?('new-window'), "expected new-window to be called"
    assert @executor.called?('main'), "expected window name in call"
    assert @executor.called?('mysession'), "expected target in call"
  end

  def test_server_running_uses_check
    @executor.stub('has-session', true)
    result = @tmux.server_running?
    assert @executor.called?('has-session'), "expected has-session to be checked"
  end

  def test_capture_pane_uses_capture
    @executor.stub('capture-pane', "line1\nline2")
    result = @tmux.capture_pane
    assert @executor.called?('capture-pane'), "expected capture-pane to be called"
    assert_equal "line1\nline2", result
  end

  def test_display_info_uses_capture
    @executor.stub('display-message', 'myvalue')
    result = @tmux.display_info('#{session_name}')
    assert @executor.called?('display-message'), "expected display-message to be called"
    assert_equal 'myvalue', result
  end

  def test_run_safe_returns_nil_for_empty_output
    @executor.stub('show-buffer', '')
    result = @tmux.show_buffer('mybuf')
    assert_nil result
  end

  def test_default_executor_is_real
    tmux = Hiiro::Tmux.new
    assert_instance_of Hiiro::Effects::Executor, tmux.instance_variable_get(:@executor)
  end

  def test_existing_positional_arg_still_works
    tmux = Hiiro::Tmux.new(:fake_hiiro)
    assert_equal :fake_hiiro, tmux.hiiro
    assert_instance_of Hiiro::Effects::Executor, tmux.instance_variable_get(:@executor)
  end
end
