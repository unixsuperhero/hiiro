require 'test_helper'
require 'json'

class ScheduleTest < Minitest::Test
  Schedule = Hiiro::Schedule
  NOW = Time.iso8601('2026-10-13T12:00:30Z')

  Status = Struct.new(:exitstatus) do
    def success? = exitstatus.zero?
  end

  def setup
    @dir = Dir.mktmpdir('hiiro-schedule-')
    Hiiro::Job.store = Hiiro::OwnedRun::Store.new(File.join(@dir, 'runs'))
    Hiiro::Job.log_dir = File.join(@dir, 'logs')
    [Hiiro::JobClaim, Hiiro::JobOutcome, Hiiro::ScheduleCheckpoint].each { |model| model.dataset.delete }
  end

  def teardown
    Hiiro::Job.store = nil
    Hiiro::Job.log_dir = nil
    FileUtils.remove_entry(@dir)
  end

  def build(fields, name = 'nightly') = Schedule.build(name, { 'cwd' => @dir }.merge(fields), source: 'test')

  def test_interval_occurrences_are_epoch_slots
    definition = build('job' => 'command', 'every' => '15m', 'command' => ['/usr/bin/true'])
    occurrence = definition.due(Time.iso8601('2026-10-13T12:14:59Z'))
    assert_equal ['2026-10-13T12:00:00Z', Time.iso8601('2026-10-13T12:00:00Z')], [occurrence.key, occurrence.at]
    assert_equal '2026-10-13T12:15:00Z', definition.due(Time.iso8601('2026-10-13T12:15:00Z')).key
    assert_equal Time.iso8601('2026-10-13T12:15:00Z'), definition.next_after(Time.iso8601('2026-10-13T12:14:59Z'))
  end

  def test_wall_clock_dst_repeated_hour_is_one_occurrence_and_skipped_time_runs_once
    fall = build('job' => 'command', 'at' => '01:30', 'timezone' => 'America/New_York', 'command' => ['/usr/bin/true'])
    first = fall.due(Time.iso8601('2026-11-01T05:45:00Z'))   # 01:45 EDT
    second = fall.due(Time.iso8601('2026-11-01T06:45:00Z'))  # 01:45 EST, the hour again
    assert_equal ['2026-11-01 01:30 America/New_York'] * 2, [first.key, second.key]
    assert_equal '2026-10-31 01:30 America/New_York', fall.due(Time.iso8601('2026-11-01T05:00:00Z')).key

    spring = build('job' => 'command', 'at' => '02:30', 'timezone' => 'America/New_York', 'command' => ['/usr/bin/true'])
    gap = spring.due(Time.iso8601('2026-03-08T08:00:00Z'))   # 04:00 EDT; 02:30 never existed
    assert_equal ['2026-03-08 02:30 America/New_York', Time.iso8601('2026-03-08T07:30:00Z')], [gap.key, gap.at]
    assert_equal Time.iso8601('2026-03-09T06:30:00Z'), spring.next_after(Time.iso8601('2026-03-08T08:00:00Z'))
    assert_nil ENV['TZ'] == 'America/New_York' ? :leaked : nil
  end

  def test_validation_refuses_unsafe_or_ambiguous_definitions
    refusals = {
      { 'job' => 'command', 'every' => '1m', 'command' => ['claude', '--dangerously-skip-permissions', 'x'] } =>
        'nightly: permission-bypass flags are not allowed in recurring recipes (--dangerously-skip-permissions)',
      { 'job' => 'queue', 'every' => '1m' } => 'nightly: a queue schedule launches agents; set agent: true to opt in',
      { 'job' => 'loop', 'every' => '1m', 'prompt' => 'summarize' } =>
        'nightly: a prompt loop needs an explicit agent: argv (e.g. [claude, -p]) or a command: argv',
      { 'job' => 'command', 'every' => '1m', 'at' => '09:00', 'command' => ['/usr/bin/true'] } =>
        'nightly: give exactly one of every: (interval) or at: (wall clock HH:MM)',
      { 'job' => 'command', 'at' => '9am', 'command' => ['/usr/bin/true'] } => 'nightly: at: must be HH:MM (24-hour)',
      { 'job' => 'command', 'at' => '09:00', 'timezone' => 'Mars/Olympus', 'command' => ['/usr/bin/true'] } =>
        'nightly: unknown timezone "Mars/Olympus"',
      { 'job' => 'command', 'every' => '1m', 'command' => ['no-such-binary-here'], 'env' => { 'PATH' => @dir } } =>
        'nightly: no-such-binary-here not found on PATH',
      { 'job' => 'command', 'every' => '1m', 'command' => ['/usr/bin/true'], 'enabled' => true } => 'nightly: unknown fields enabled',
    }
    refusals.each do |fields, message|
      error = assert_raises(Hiiro::Error) { build(fields) }
      assert_equal message, error.message
    end
  end

  def test_builtin_jobs_reuse_existing_one_shot_workers_with_absolute_paths
    root = File.expand_path('../..', __dir__)
    base = [RbConfig.ruby, '-I', File.join(root, 'lib')]
    assert_equal [*base, File.join(root, 'bin/h-remind'), 'check'], build('job' => 'reminders', 'every' => '1m').program
    assert_equal [*base, File.join(root, 'bin/h-pr-monitor'), '--once', '--queue-fixes'],
      build('job' => 'pr-monitor', 'every' => '5m', 'args' => ['--queue-fixes']).program
    queue = build('job' => 'queue', 'every' => '1m', 'agent' => true, 'max_running' => 2)
    assert_equal [*base, File.join(root, 'exe/h'), 'queue', 'tick', '--max', '2'], queue.program
    assert queue.agent
    assert_equal ['/bin/sh', '-c', 'x'], build('job' => 'command', 'every' => '1m', 'command' => %w[sh -c x], 'env' => { 'PATH' => '/bin' }).program
  end

  def test_plist_names_only_sandboxed_absolute_paths_and_owned_label
    definition = build('job' => 'command', 'every' => '90s', 'command' => ['/bin/echo', 'a&b'], 'env' => { 'HIIRO_TEST_DB' => 'sqlite:///x.db' })
    launchd = Schedule::Launchd.new(prefix: 'com.hiiro.rehiiro-test.unit', agents_dir: File.join(@dir, 'agents'))
    root = File.expand_path('../..', __dir__)
    expected = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>com.hiiro.rehiiro-test.unit.nightly</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{RbConfig.ruby}</string>
          <string>-I</string>
          <string>#{root}/lib</string>
          <string>#{root}/bin/h-schedule</string>
          <string>run</string>
          <string>nightly</string>
          <string>--scheduled</string>
        </array>
        <key>WorkingDirectory</key>
        <string>#{@dir}</string>
        <key>EnvironmentVariables</key>
        <dict>
          <key>HIIRO_TEST_DB</key>
          <string>sqlite:///x.db</string>
          <key>HOME</key>
          <string>#{Dir.home}</string>
          <key>LANG</key>
          <string>#{ENV.fetch('LANG', 'en_US.UTF-8')}</string>
          <key>PATH</key>
          <string>#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin</string>
        </dict>
        <key>StartInterval</key>
        <integer>90</integer>
        <key>RunAtLoad</key>
        <false/>
        <key>ProcessType</key>
        <string>Background</string>
        <key>StandardOutPath</key>
        <string>#{Dir.home}/.local/share/hiiro/schedules/nightly.launchd.log</string>
        <key>StandardErrorPath</key>
        <string>#{Dir.home}/.local/share/hiiro/schedules/nightly.launchd.log</string>
      </dict>
      </plist>
    XML
    assert_equal expected, launchd.plist(definition)
    assert_includes launchd.plan(definition), "runs:      /bin/echo a\\&b"
  end

  def test_enable_and_disable_touch_only_the_owned_plist_and_report_registration_failure
    calls = []
    results = { 'bootstrap' => [['Bootstrap failed: 5: Input/output error', Status.new(5)], ['', Status.new(0)]],
                'bootout' => [['', Status.new(0)]] }
    runner = ->(*argv) { calls << argv; results.fetch(argv[1]).shift }
    agents = File.join(@dir, 'agents')
    FileUtils.mkdir_p(agents)
    File.write(File.join(agents, 'com.example.other.plist'), 'unrelated')
    launchd = Schedule::Launchd.new(prefix: 'com.hiiro.rehiiro-test.unit', agents_dir: agents, runner: runner)
    definition = build('job' => 'command', 'every' => '1m', 'command' => ['/usr/bin/true'])

    error = assert_raises(Hiiro::Error) { Schedule.enable(definition, launchd: launchd) }
    assert_equal 'launchctl bootstrap com.hiiro.rehiiro-test.unit.nightly failed (exit 5): Bootstrap failed: 5: Input/output error; not enabled', error.message
    assert_nil Hiiro::ScheduleCheckpoint.for('nightly')
    assert_equal ['com.example.other.plist'], Dir.children(agents)

    Schedule.enable(definition, launchd: launchd)
    checkpoint = Hiiro::ScheduleCheckpoint.for('nightly')
    assert_equal [true, 'com.hiiro.rehiiro-test.unit.nightly'], [checkpoint.enabled, checkpoint.label]
    assert_equal ['com.example.other.plist', 'com.hiiro.rehiiro-test.unit.nightly.plist'], Dir.children(agents).sort
    assert_equal launchd.plist(definition), File.read(File.join(agents, 'com.hiiro.rehiiro-test.unit.nightly.plist'))

    Schedule.disable('nightly', launchd: launchd)
    refute Hiiro::ScheduleCheckpoint.for('nightly').enabled
    assert_equal ['com.example.other.plist'], Dir.children(agents)
    assert_equal 'unrelated', File.read(File.join(agents, 'com.example.other.plist'))
    plist = File.join(agents, 'com.hiiro.rehiiro-test.unit.nightly.plist')
    assert_equal [['launchctl', 'bootstrap', "gui/#{Process.uid}", plist]] * 2 +
      [['launchctl', 'bootout', "gui/#{Process.uid}/com.hiiro.rehiiro-test.unit.nightly"]], calls
  end

  def test_tick_runs_each_occurrence_once_and_respects_enable_and_missed_policy
    definition = build('job' => 'command', 'every' => '1m', 'command' => ['/bin/sh', '-c', 'echo tick >> ticks.txt'])
    assert_equal({ status: :disabled }, Schedule.tick(definition, now: NOW, scheduled: true))
    refute File.exist?(File.join(@dir, 'ticks.txt'))

    result = Schedule.tick(definition, now: NOW)
    assert_equal [:ran, 'completed'], [result[:status], result[:outcome].outcome]
    assert_equal({ 'trigger' => 'manual', 'job' => 'command', 'late_seconds' => 30, 'cwd' => @dir,
                   'command' => "/bin/sh -c #{Shellwords.escape('echo tick >> ticks.txt')}" }, result[:outcome].context)
    assert_equal :not_due, Schedule.tick(definition, now: NOW + 20)[:status]
    assert_equal ["tick\n"], File.readlines(File.join(@dir, 'ticks.txt'))
    checkpoint = Hiiro::ScheduleCheckpoint.for('nightly')
    assert_equal ['2026-10-13T12:00:00Z', 'completed', result[:outcome].run_id], checkpoint.values.values_at(:last_due, :last_outcome, :last_run_id)

    skip = build({ 'job' => 'command', 'every' => '1h', 'missed' => 'skip', 'grace' => '5m', 'command' => ['/bin/sh', '-c', 'echo late >> late.txt'] }, 'skipper')
    assert_equal :missed, Schedule.tick(skip, now: Time.iso8601('2026-10-13T12:10:00Z'))[:status]
    refute File.exist?(File.join(@dir, 'late.txt'))
    assert_equal ['2026-10-13T12:00:00Z', nil, 'skipped: 600s late (grace 300s)'],
      Hiiro::ScheduleCheckpoint.for('skipper').values.values_at(:last_due, :last_outcome, :detail)
    run_once = build({ 'job' => 'command', 'every' => '1h', 'grace' => '5m', 'command' => ['/bin/sh', '-c', 'echo late >> late.txt'] }, 'hourly')
    assert_equal 'completed', Schedule.tick(run_once, now: Time.iso8601('2026-10-13T12:10:00Z'))[:outcome].outcome
    assert_equal ["late\n"], File.readlines(File.join(@dir, 'late.txt'))
  end

  def test_failure_notification_is_recorded_without_changing_the_outcome
    sent = []
    deliveries = [false, true]
    Hiiro::Notification.stub(:deliver, ->(args) { sent << args; deliveries.shift }) do
      definition = build('job' => 'command', 'every' => '1m', 'notify' => 'failures', 'command' => ['/bin/sh', '-c', 'exit 2'])
      first = Schedule.tick(definition, now: NOW)[:outcome]
      assert_equal ['failed', 'failed'], [first.outcome, first.notification]
      second = Schedule.tick(definition, now: NOW + 60)[:outcome]
      assert_equal ['failed', 'delivered'], [second.outcome, second.notification]
      quiet = build({ 'job' => 'command', 'every' => '1m', 'notify' => 'failures', 'command' => ['/usr/bin/true'] }, 'quiet')
      quiet_outcome = Schedule.tick(quiet, now: NOW)[:outcome]
      assert_equal ['completed', nil], [quiet_outcome.outcome, quiet_outcome.notification], quiet_outcome.values.inspect
    end
    assert_equal [['-t', 'hiiro nightly', '-m', 'failed exit 2: exit 2']] * 2, sent
  end

  def test_loop_configs_are_definitions_and_invalid_ones_are_listed_not_run
    home = File.join(@dir, 'home')
    FileUtils.mkdir_p([File.join(home, 'ai/loops/prs'), File.join(home, 'ai/loops/old'), File.join(home, '.config/hiiro')])
    File.write(File.join(home, 'ai/loops/prs/config.yml'), { 'name' => 'prs', 'frequency' => '5m', 'prompt' => 'Summarize PRs', 'agent' => ['/bin/echo', '-n'] }.to_yaml)
    File.write(File.join(home, 'ai/loops/old/config.yml'), { 'name' => 'old', 'frequency' => '10m', 'prompt' => 'legacy prompt' }.to_yaml)
    Dir.stub(:home, home) do
      definitions = Schedule.definitions
      assert_equal ['/bin/echo', '-n', 'Summarize PRs'], definitions['loop-prs'].program
      assert_equal [300, true, true], definitions['loop-prs'].to_h.values_at(:every, :agent, :keep_logs)
      assert_equal 'loop-old: a prompt loop needs an explicit agent: argv (e.g. [claude, -p]) or a command: argv', definitions['loop-old'].error
      assert_raises(Hiiro::Error) { Schedule.definition('loop-old') }
    end
  end
end
