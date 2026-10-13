require 'test_helper'

class ServiceManagerHerdrTest < Minitest::Test
  include OwnedRunHelpers

  def setup
    @dir = File.realpath(Dir.mktmpdir('services-'))
    @config_file = File.join(@dir, 'services.yml')
    @state_file = File.join(@dir, 'state', 'running.yml')
    @store = run_store(@dir)
  end

  def teardown
    @managers&.each do |manager|
      manager.instances.each do |instance|
        process = manager.run_for(instance)&.process
        Process.kill('KILL', -process.pid) if process&.alive?
      rescue Errno::ESRCH
        nil
      end
    end
    @terminal&.wait_all
    FileUtils.remove_entry(@dir)
  end

  def configure(services)
    File.write(@config_file, YAML.dump(services))
  end

  def manager(directory: @dir, herdr: Hiiro::Herdr.new(executor: Hiiro::Effects::NullExecutor.new))
    context = Hiiro::TaskLocation.for(nil, root: @dir, invocation_directory: directory,
      terminal: Hiiro::Herdr::Location.new).with_directory(directory, source: :override)
    sm = Hiiro::ServiceManager.new(config_file: @config_file, state_file: @state_file, herdr: herdr, context: context)
    sm.launcher = Hiiro::OwnedRun::Launcher.new(store: @store, herdr: herdr)
    (@managers ||= []) << sm
    sm
  end

  def wait_until(timeout: 10)
    deadline = Time.now + timeout
    sleep 0.02 until yield || Time.now > deadline
    yield
  end

  def test_start_in_herdr_records_location_and_runs_the_supervisor_in_the_root_pane
    configure('web' => { 'base_dir' => @dir, 'start' => "echo up > #{File.join(@dir, 'up').shellescape}" })
    @terminal = FakeHerdrTerminal.new
    @terminal.stub('tab create', JSON.generate('result' => {
      'tab' => { 'tab_id' => 'w1:t3', 'workspace_id' => 'w1' },
      'root_pane' => { 'pane_id' => 'w1:p3', 'workspace_id' => 'w1', 'tab_id' => 'w1:t3' },
    }))
    herdr = Hiiro::Herdr.new(executor: @terminal)
    workspace = Hiiro::Herdr::Workspace.new({ 'workspace_id' => 'w1', 'label' => 'development' }, client: herdr)
    sm = manager(herdr: herdr)

    assert sm.start('web', herdr_info: { workspace: workspace }, skip_env: true)

    instance = sm.instances.fetch(0)
    assert_equal 'w1', instance.record['herdr_workspace']
    assert_equal 'w1:t3', instance.record['herdr_tab']
    assert_equal 'w1:p3', instance.record['herdr_pane']
    pane_run = @terminal.calls_to(:run).find { |call| call[:args][0, 3] == %w[herdr pane run] }[:args]
    assert_equal ['herdr', 'pane', 'run', 'w1:p3'], pane_run[0, 4]
    assert_includes pane_run[4], @store.path_for(instance.run_id)
    assert_equal 'completed exit 0', wait_for_run(@store, instance.run_id).summary
    assert_equal "up\n", File.read(File.join(@dir, 'up'))
  end

  def test_same_definition_in_two_directories_runs_and_stops_independently
    alpha = File.join(@dir, 'alpha')
    beta = File.join(@dir, 'beta')
    FileUtils.mkdir_p([alpha, beta])
    configure('web' => { 'start' => 'exec sleep 30', 'cleanup' => ['pwd > cleaned'] })
    first = manager(directory: alpha)
    second = manager(directory: beta)

    assert first.start('web', skip_env: true)
    assert second.start('web', skip_env: true)
    refute first.start('web', skip_env: true)

    instances = first.instances
    assert_equal 2, instances.size
    assert_equal [alpha, beta], instances.map(&:directory).sort
    refute_equal instances[0].run_id, instances[1].run_id
    alpha_run = first.run_for(instances.find { |i| i.directory == alpha })
    beta_run = first.run_for(instances.find { |i| i.directory == beta })
    assert alpha_run.process.alive?
    assert beta_run.process.alive?

    error = assert_raises(Hiiro::Error) { manager(directory: @dir).stop('web') }
    assert_match(/Several 'web' instances/, error.message)

    assert first.stop('web')
    refute alpha_run.process.alive?
    assert_equal 'failed signal TERM', @store.find(alpha_run.id).summary
    assert_equal alpha, File.read(File.join(alpha, 'cleaned')).strip
    assert beta_run.process.alive?
    assert_equal [beta], first.instances.map(&:directory)
    refute File.exist?(File.join(beta, 'cleaned'))
  end

  def test_stop_refuses_to_signal_a_reused_pid
    configure('web' => { 'start' => 'true' })
    sm = manager
    request = Hiiro::OwnedRun::LaunchRequest.new(owner: { kind: 'service' },
      command: Hiiro::CommandSpecification.new('true'), process_group: true)
    run = @store.create(Hiiro::OwnedRun.allocate(request))
    @store.update(run.id) { |record| record.start(Hiiro::OwnedRun::ProcessIdentity.new(pid: Process.pid, started: 'Thu Jan  1 00:00:00 1970')) }
    FileUtils.mkdir_p(File.dirname(@state_file))
    File.write(@state_file, YAML.dump('web@reused' => { 'definition' => 'web', 'directory' => @dir, 'run_id' => run.id }))

    out, = capture_io { assert sm.stop('web') }
    assert_match(/Process #{Process.pid} for 'web@reused' is gone or was reused; not signalling it/, out)
    assert_equal 'failed: exited without a recorded status', @store.find(run.id).summary
    assert_equal [], sm.instances
  end

  def test_unowned_legacy_state_is_not_stopped_by_label
    configure('web' => { 'start' => 'true', 'stop' => 'touch stopped' })
    FileUtils.mkdir_p(File.dirname(@state_file))
    File.write(@state_file, YAML.dump('web' => { 'directory' => @dir, 'herdr_pane' => 'w1:p1' }))
    sm = manager
    out, = capture_io { refute sm.stop('web') }
    assert_match(/has no owned run/, out)
    refute File.exist?(File.join(@dir, 'stopped'))
    assert_equal ['web'], sm.instances.map(&:key)
  end

  def test_preparation_failure_is_the_runs_outcome
    configure('web' => { 'init' => ['exit 3'], 'start' => 'touch started' })
    sm = manager
    capture_io { assert sm.start('web', skip_env: true) }
    run = wait_for_run(@store, sm.instances.first.run_id)
    assert_equal 'failed exit 3', run.summary
    refute File.exist?(File.join(@dir, 'started'))
    out, = capture_io { sm.status('web') }
    assert_includes out, "Status: failed exit 3"
  end

  def test_ready_only_from_configured_probe_and_stop_waits_for_exit
    configure('web' => {
      'start' => "trap 'sleep 0.3; exit 0' TERM; touch up; while true; do sleep 0.05; done",
      'ready' => 'test -f up',
    })
    sm = manager
    capture_io { assert sm.start('web', skip_env: true) }
    run_id = sm.instances.first.run_id
    assert wait_until { @store.find(run_id).state == 'ready' }

    out, = capture_io { assert sm.stop('web') }
    run = @store.find(run_id)
    refute run.process.alive?
    assert_equal 'completed exit 0', run.summary
    assert_match(/Stopped service 'web@\h{8}' \(completed exit 0\)/, out)
  end
end
