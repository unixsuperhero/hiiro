require 'test_helper'
require 'json'

class JobTest < Minitest::Test
  NOW = Time.iso8601('2026-10-13T12:00:00Z')

  def setup
    @dir = Dir.mktmpdir('hiiro-job-')
    Hiiro::Job.store = Hiiro::OwnedRun::Store.new(File.join(@dir, 'runs'))
    Hiiro::Job.log_dir = File.join(@dir, 'logs')
    Hiiro::JobClaim.dataset.delete
    Hiiro::JobOutcome.dataset.delete
  end

  def teardown
    Hiiro::Job.store = nil
    Hiiro::Job.log_dir = nil
    FileUtils.remove_entry(@dir)
  end

  def sh(text) = Hiiro::CommandSpecification.new('/bin/sh', '-c', text, cwd: @dir)

  def execute(text, occurrence: 'o1', timeout: 10, **options)
    Hiiro::Job.execute('nightly', occurrence, command: sh(text), timeout: timeout, now: NOW, **options)
  end

  def test_completed_run_records_outcome_and_artifacts_and_drops_its_log
    outcome = execute('echo hello; printf report > out.txt', artifacts: ['out.txt', 'missing.txt'], context: { 'trigger' => 'manual' })
    assert_equal ['nightly', 'o1', 1, 'completed', 0, nil, 'exit 0', nil],
      outcome.values.values_at(:definition, :occurrence, :attempt, :outcome, :exit_code, :signal, :detail, :log_path)
    assert_equal [{ 'path' => File.join(@dir, 'out.txt'), 'bytes' => 6 }], outcome.artifacts
    assert_equal({ 'trigger' => 'manual', 'cwd' => @dir, 'command' => "/bin/sh -c #{Shellwords.escape('echo hello; printf report > out.txt')}" }, outcome.context)
    assert_equal NOW.utc.iso8601, Hiiro::JobClaim.first.claimed_at
    assert_equal 'completed', Hiiro::JobClaim.first.outcome
    assert_equal [], Dir.glob(File.join(@dir, 'logs/**/*.log'))
  end

  def test_failed_run_keeps_its_log_and_exit_status
    outcome = execute('echo boom >&2; exit 3')
    assert_equal ['failed', 3, 'exit 3'], outcome.values.values_at(:outcome, :exit_code, :detail)
    assert_equal "boom\n", File.read(outcome.log_path)
    assert_equal File.join(@dir, 'logs/nightly', "#{outcome.run_id}.log"), outcome.log_path
  end

  def test_unstartable_command_is_startup_failed
    outcome = Hiiro::Job.execute('nightly', 'o1', command: Hiiro::CommandSpecification.new('/nonexistent/prog'), timeout: 5, now: NOW)
    assert_equal ['startup-failed', nil, '/nonexistent/prog: No such file or directory - /nonexistent/prog'],
      outcome.values.values_at(:outcome, :exit_code, :detail)
    assert_match(/not started/, File.read(outcome.log_path))
  end

  def test_timeout_interrupts_the_whole_process_group
    marker = File.join(@dir, 'grandchild.pid')
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = execute("sleep 30 & echo $! > #{marker}; wait", timeout: 1)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 8
    assert_equal ['interrupted', nil, 'TERM', 'timed out after 1s'], outcome.values.values_at(:outcome, :exit_code, :signal, :detail)
    grandchild = File.read(marker).to_i
    assert_raises(Errno::ESRCH) { Process.kill(0, grandchild) }
  end

  def test_completed_occurrence_is_never_run_again_and_a_live_holder_is_an_overlap
    execute('true')
    assert_nil execute('echo again > again.txt')
    refute File.exist?(File.join(@dir, 'again.txt'))

    Hiiro::Job.claim('nightly', 'o2', run_id: 'run-holder', now: NOW)
    skipped = execute('echo second > second.txt', occurrence: 'o2')
    assert_equal ['skipped-overlap', 'occurrence held by run-holder'], skipped.values.values_at(:outcome, :detail)
    refute File.exist?(File.join(@dir, 'second.txt'))
  end

  def test_concurrency_bound_counts_other_live_occurrences
    Hiiro::Job.claim('nightly', 'o1', run_id: 'run-holder', now: NOW)
    skipped = execute('true', occurrence: 'o2', max_concurrent: 1)
    assert_equal ['skipped-overlap', '1 already running'], skipped.values.values_at(:outcome, :detail)
    assert_equal 'completed', execute('true', occurrence: 'o3', max_concurrent: 2).outcome
  end

  def test_dead_claimant_becomes_stale_owner_and_the_occurrence_is_reclaimed
    pid = Process.spawn('true')
    Process.wait(pid)
    Hiiro::JobClaim.create(definition: 'nightly', occurrence: 'o1', run_id: 'run-dead', attempt: 1,
      claimant: JSON.generate('pid' => pid, 'started' => 'gone'), claimed_at: '2026-10-13T11:00:00Z')
    outcome = execute('true')
    stale = Hiiro::JobOutcome.first(run_id: 'run-dead')
    assert_equal ['stale-owner', "claimant #{pid} exited before recording an outcome", '2026-10-13T11:00:00Z'],
      stale.values.values_at(:outcome, :detail, :started_at)
    assert_equal ['completed', 2], outcome.values.values_at(:outcome, :attempt)
    assert_equal [[outcome.run_id, 2, 'completed']], Hiiro::JobClaim.select_map(%i[run_id attempt outcome])
  end

  def test_run_finished_after_its_worker_died_records_the_real_outcome
    request = Hiiro::OwnedRun::LaunchRequest.new(id: 'run-orphan', owner: { kind: 'job' }, command: sh('exit 4'))
    run = Hiiro::OwnedRun.allocate(request)
    run.start(Hiiro::OwnedRun::ProcessIdentity.new(pid: 1, started: 'x'))
    run.finish(Hiiro::ProcessOutcome.new(exit_code: 4))
    Hiiro::Job.store.create(run)
    Hiiro::JobClaim.create(definition: 'nightly', occurrence: 'o1', run_id: 'run-orphan', attempt: 1,
      claimant: JSON.generate('pid' => 999_999, 'started' => 'gone'), claimed_at: '2026-10-13T11:00:00Z')
    status, = Hiiro::Job.claim('nightly', 'o1', run_id: 'run-next', now: NOW)
    assert_equal :claimed, status
    assert_equal ['failed', 4, 'recorded after its worker exited'],
      Hiiro::JobOutcome.first(run_id: 'run-orphan').values.values_at(:outcome, :exit_code, :detail)
  end

  def test_perform_records_in_process_work
    outcome = Hiiro::Job.perform('reminder:1', '2026-10-13T12:00:00Z', context: { 'message' => 'm' }, now: NOW) { ['failed', 'no notifier'] }
    assert_equal ['failed', 'no notifier', 1], outcome.values.values_at(:outcome, :detail, :attempt)
    retried = Hiiro::Job.perform('reminder:1', '2026-10-13T12:00:00Z', now: NOW) { ['completed', 'delivered'] }
    assert_equal ['completed', 2], retried.values.values_at(:outcome, :attempt)
    assert_nil Hiiro::Job.perform('reminder:1', '2026-10-13T12:00:00Z', now: NOW) { flunk 'ran twice' }
  end
end
