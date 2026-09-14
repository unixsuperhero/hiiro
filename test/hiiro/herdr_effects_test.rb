require 'test_helper'

class HerdrEffectsTest < Minitest::Test
  def setup
    @executor = Hiiro::Effects::NullExecutor.new
    @herdr = Hiiro::Herdr.new(executor: @executor)
  end

  def test_parses_workspace_list_json
    @executor.stub('workspace list', JSON.generate(
      'result' => {
        'type' => 'workspace_list',
        'workspaces' => [
          {
            'workspace_id' => 'w1',
            'number' => 1,
            'label' => 'hiiro',
            'focused' => true,
            'pane_count' => 2,
            'tab_count' => 1,
            'active_tab_id' => 'w1:t1',
            'agent_status' => 'working',
          },
        ],
      },
    ))

    workspace = @herdr.workspaces.first

    assert_equal 'w1', workspace.id
    assert_equal 'hiiro', workspace.name
    assert_equal 2, workspace.pane_count
    assert workspace.focused?
  end

  def test_parses_tab_and_pane_lists
    @executor.stub('tab list', JSON.generate(
      'result' => {
        'tabs' => [
          {
            'tab_id' => 'w1:t1', 'workspace_id' => 'w1', 'number' => 1,
            'label' => 'code', 'focused' => true, 'pane_count' => 1,
            'agent_status' => 'idle',
          },
        ],
      },
    ))
    @executor.stub('pane list', JSON.generate(
      'result' => {
        'panes' => [
          {
            'pane_id' => 'w1:p1', 'terminal_id' => 'term-1',
            'workspace_id' => 'w1', 'tab_id' => 'w1:t1', 'focused' => true,
            'cwd' => '/tmp', 'agent_status' => 'idle', 'revision' => 1,
          },
        ],
      },
    ))

    assert_equal 'w1:t1', @herdr.tabs.first.id
    assert_equal 'w1:p1', @herdr.panes.first.id
    assert_equal '/tmp', @herdr.panes.first.cwd
  end

  def test_new_workspace_uses_herdr_workspace_create
    @executor.stub('workspace create', JSON.generate(
      'result' => {
        'workspace' => {
          'workspace_id' => 'w2', 'number' => 2, 'label' => 'feature',
          'focused' => true, 'pane_count' => 1, 'tab_count' => 1,
          'active_tab_id' => 'w2:t1', 'agent_status' => 'idle',
        },
      },
    ))

    workspace = @herdr.new_workspace('feature', start_directory: '/code/feature')

    assert_equal 'w2', workspace.id
    call = @executor.calls_to(:capture).last[:args]
    assert_equal ['herdr', 'workspace', 'create', '--label', 'feature', '--cwd', '/code/feature', '--focus'], call
  end

  def test_new_tab_runs_command_in_returned_root_pane
    @executor.stub('tab create', JSON.generate(
      'result' => {
        'tab' => {
          'tab_id' => 'w1:t2', 'workspace_id' => 'w1', 'number' => 2,
          'label' => 'tests', 'focused' => false, 'pane_count' => 1,
          'agent_status' => 'idle',
        },
        'root_pane' => {
          'pane_id' => 'w1:p2', 'terminal_id' => 'term-2',
          'workspace_id' => 'w1', 'tab_id' => 'w1:t2', 'focused' => false,
          'agent_status' => 'idle', 'revision' => 1,
        },
      },
    ))

    @herdr.new_tab(name: 'tests', workspace: 'w1', command: 'bundle exec rake test', focus: false)

    run_call = @executor.calls_to(:run).last[:args]
    assert_equal ['herdr', 'pane', 'run', 'w1:p2', 'bundle exec rake test'], run_call
  end

  def test_split_pane_maps_vertical_split_to_right
    @executor.stub('pane split', JSON.generate(
      'result' => {
        'pane' => {
          'pane_id' => 'w1:p2', 'terminal_id' => 'term-2',
          'workspace_id' => 'w1', 'tab_id' => 'w1:t1', 'focused' => true,
          'agent_status' => 'idle', 'revision' => 1,
        },
      },
    ))

    pane = @herdr.vsplit_window(size: '40%', command: 'claude')

    assert_equal 'w1:p2', pane.id
    split_call = @executor.calls_to(:capture).first[:args]
    assert_equal ['herdr', 'pane', 'split', '--current', '--direction', 'right', '--ratio', '0.4', '--focus'], split_call
    assert_equal ['herdr', 'pane', 'run', 'w1:p2', 'claude'], @executor.calls_to(:run).last[:args]
  end

  def test_default_executor_is_real
    herdr = Hiiro::Herdr.new
    assert_instance_of Hiiro::Effects::Executor, herdr.instance_variable_get(:@executor)
  end
end
