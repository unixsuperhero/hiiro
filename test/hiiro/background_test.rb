require 'test_helper'

class BackgroundTest < Minitest::Test
  include OwnedRunHelpers

  def setup
    @dir = File.realpath(Dir.mktmpdir('background-'))
    @store = run_store(@dir)
    @reservations = Hiiro::PaneReservations.new(File.join(@dir, 'reservations'))
    @executor = FakeHerdrTerminal.new
    @herdr = Hiiro::Herdr.new(executor: @executor)
    @launcher = Hiiro::OwnedRun::Launcher.new(store: @store, herdr: @herdr)
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
    @executor.wait_all
    FileUtils.remove_entry(@dir)
  end

  def busy(pane_id, cmdline)
    @executor.stub("process-info --pane #{pane_id}", JSON.generate('result' => { 'process_info' =>
      { 'shell_pid' => 1, 'foreground_process_group_id' => 2, 'foreground_processes' => [{ 'pid' => 2, 'cmdline' => cmdline }] } }))
  end

  def idle(pane_id)
    @executor.stub("process-info --pane #{pane_id}", JSON.generate('result' => { 'process_info' =>
      { 'shell_pid' => 1, 'foreground_process_group_id' => 1, 'foreground_processes' => [{ 'pid' => 1, 'cmdline' => '-zsh' }] } }))
  end

  def pane_runs
    @executor.calls_to(:run).map { |call| call[:args] }.select { |args| args[0, 3] == %w[herdr pane run] }
  end

  def background(*cmd, **opts)
    Hiiro::Background.run(*cmd, client: @herdr, launcher: @launcher, reservations: @reservations, **opts)
  end

  def test_reuses_the_first_idle_shell_pane_and_releases_it_on_completion
    busy('wC:p1', 'rake test')
    idle('wC:p2')
    run = background('/bin/sh', '-c', 'pwd > where', dir: @dir)
    assert_equal ['wC:p2'], pane_runs.map { |args| args[3] }
    assert_equal 'wC:p2', run.terminal.pane_id
    assert_equal 'completed exit 0', wait_for_run(@store, run.id).summary
    assert_equal @dir, File.read(File.join(@dir, 'where')).strip
    assert_nil @reservations.holder('wC:p2')
  end

  def test_opens_a_new_unfocused_tab_only_when_every_pane_is_busy
    busy('wC:p1', 'rake test')
    busy('wC:p2', 'vim notes.md')
    run = background('/bin/sh', '-c', 'exit 3')
    creates = @executor.calls.map { |call| call[:args] }.select { |args| args[1..2] == %w[tab create] }
    assert_equal [%w[herdr tab create --workspace wC --label /bin/sh --no-focus]], creates
    assert_equal ['wC:p3'], pane_runs.map { |args| args[3] }
    assert_equal 'failed exit 3', wait_for_run(@store, run.id).summary
  end

  def test_concurrent_launches_never_share_a_reserved_pane
    idle('wC:p1')
    idle('wC:p2')
    gate = File.join(@dir, 'gate')
    command = ['/bin/sh', '-c', "while [ ! -f #{gate.shellescape} ]; do sleep 0.02; done"]
    start = Queue.new
    threads = 3.times.map do
      Thread.new do
        start.pop
        background(*command)
      end
    end
    3.times { start << true }
    runs = threads.map(&:value)
    assert_equal %w[wC:p1 wC:p2 wC:p3], runs.map { |run| run.terminal.pane_id }.sort
    assert_equal 3, runs.map(&:id).uniq.size
    File.write(gate, '')
    runs.each { |run| assert_equal 'completed exit 0', wait_for_run(@store, run.id).summary }
    deadline = Time.now + 10
    sleep 0.02 while Time.now < deadline && %w[wC:p1 wC:p2].any? { |pane| @reservations.holder(pane) }
    assert_equal [nil, nil], [@reservations.holder('wC:p1'), @reservations.holder('wC:p2')]
  end

  def test_undelivered_command_is_reported_and_releases_the_pane
    idle('wC:p1')
    @executor.deliver = false
    error = assert_raises(Hiiro::OwnedRun::LaunchError) { background('true') }
    assert_equal 'failed: Herdr did not run the command in pane wC:p1', error.run.summary
    assert_nil @reservations.holder('wC:p1')
  end

  def test_outside_herdr_spawns_a_detached_owned_run
    ENV['HERDR_ENV'] = nil
    run = background('/bin/sh', '-c', 'echo detached > out; exit 0', dir: @dir)
    assert_equal({ 'kind' => 'detached' }, run.placement)
    assert_equal 'completed exit 0', wait_for_run(@store, run.id).summary
    assert_equal "detached\n", File.read(File.join(@dir, 'out'))
    assert_empty pane_runs
  end
end
