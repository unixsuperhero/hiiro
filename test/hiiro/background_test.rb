require 'test_helper'

class BackgroundTest < Minitest::Test
  def setup
    @executor = Hiiro::Effects::NullExecutor.new
    @herdr = Hiiro::Herdr.new(executor: @executor)
    @executor.stub('workspace list', JSON.generate('result' => { 'workspaces' => [
      { 'workspace_id' => 'wC', 'label' => 'h-bg', 'focused' => false, 'pane_count' => 2, 'tab_count' => 2 },
    ] }))
    @executor.stub('pane list --workspace wC', JSON.generate('result' => { 'panes' => [
      { 'pane_id' => 'wC:p1', 'workspace_id' => 'wC', 'tab_id' => 'wC:t1' },
      { 'pane_id' => 'wC:p2', 'workspace_id' => 'wC', 'tab_id' => 'wC:t2' },
    ] }))
    @executor.stub('tab create', JSON.generate('result' => { 'tab' => { 'tab_id' => 'wC:t3' }, 'root_pane' => { 'pane_id' => 'wC:p3' } }))
    @previous = ENV['HERDR_ENV']
    ENV['HERDR_ENV'] = '1'
  end

  def teardown
    ENV['HERDR_ENV'] = @previous
  end

  def busy(pane_id, cmdline)
    @executor.stub("process-info --pane #{pane_id}", JSON.generate('result' => { 'process_info' =>
      { 'shell_pid' => 1, 'foreground_process_group_id' => 2, 'foreground_processes' => [{ 'pid' => 2, 'cmdline' => cmdline }] } }))
  end

  def idle(pane_id)
    @executor.stub("process-info --pane #{pane_id}", JSON.generate('result' => { 'process_info' =>
      { 'shell_pid' => 1, 'foreground_process_group_id' => 1, 'foreground_processes' => [{ 'pid' => 1, 'cmdline' => '-zsh' }] } }))
  end

  def runs
    @executor.calls.select { |call| call[:method] == :run }.map { |call| call[:args] }
  end

  def test_reuses_the_first_idle_shell_pane_in_the_bg_workspace
    busy('wC:p1', 'rake test')
    idle('wC:p2')
    Hiiro::Background.run('zsh', '-lc', 'echo hi', dir: '/tmp/work', client: @herdr)
    assert_equal [['herdr', 'pane', 'run', 'wC:p2', "cd /tmp/work && zsh -lc echo\\ hi"]], runs
  end

  def test_opens_a_new_unfocused_tab_only_when_every_pane_is_busy
    busy('wC:p1', 'rake test')
    busy('wC:p2', 'vim notes.md')
    Hiiro::Background.run('zsh', '-lc', 'echo hi', client: @herdr)
    creates = @executor.calls.map { |call| call[:args] }.select { |args| args[1..2] == %w[tab create] }
    assert_equal [%w[herdr tab create --workspace wC --label zsh --no-focus]], creates
    assert_equal [['herdr', 'pane', 'run', 'wC:p3', 'zsh -lc echo\\ hi']], runs
  end
end
