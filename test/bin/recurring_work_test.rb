require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'sequel'

# Real h-schedule, h-remind, h queue, h-loop, and h-notify processes against a
# temporary HOME and database. Every agent and notifier is a fixture script.
class RecurringWorkTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('hiiro-recurring-'))
    @home = File.join(@root, 'home')
    @work = File.join(@root, 'work')
    @fix = File.join(@root, 'fix')
    FileUtils.mkdir_p([@home, @work, @fix, File.join(@home, '.config/hiiro')])
    fixture('terminal-notifier', <<~SH)
      #!/bin/sh
      [ -n "$NOTIFY_SLEEP" ] && sleep "$NOTIFY_SLEEP"
      [ -e "#{@root}/notifier-broken" ] && exit 1
      printf '%s\\n' "$*" >> "#{@root}/notify.log"
    SH
    fixture('omp', <<~SH)
      #!/bin/sh
      echo "$*" >> "#{@root}/omp.log"
      echo "agent saw: $(head -1 "${2#@}")"
      sleep "${OMP_SLEEP:-0}"
      exit "${OMP_EXIT:-0}"
    SH
    @db_path = File.join(@root, 'hiiro.db')
  end

  def teardown
    @db&.disconnect
    FileUtils.remove_entry(@root)
  end

  def fixture(name, body)
    path = File.join(@fix, name)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def env(extra = {})
    { 'HOME' => @home, 'LANG' => 'en_US.UTF-8', 'TZ' => 'UTC', 'HIIRO_TEST_DB' => "sqlite://#{@db_path}",
      'PATH' => "#{@fix}:#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin" }.merge(extra)
  end

  def argv(bin, *args) = [RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, bin), *args]

  def h(bin, *args, extra: {})
    out, status = Open3.capture2e(env(extra), *argv(bin, *args), chdir: @work, unsetenv_others: true)
    [out, status.exitstatus]
  end

  # Starts every command at once and returns [[output, exit], …] in order.
  def concurrently(*commands, extra: {})
    started = commands.map do |bin, *args|
      reader, writer = IO.pipe
      pid = Process.spawn(env(extra), *argv(bin, *args), chdir: @work, unsetenv_others: true, out: writer, err: writer)
      writer.close
      [pid, reader]
    end
    started.map do |pid, reader|
      output = reader.read
      Process.wait(pid)
      [output, $?.exitstatus]
    end
  end

  def db = @db ||= Sequel.sqlite(@db_path)

  def schedules(yaml) = File.write(File.join(@home, '.config/hiiro/schedules.yml'), yaml)

  def test_overlapping_schedule_runs_claim_one_occurrence_and_record_real_failures
    schedules(<<~YAML)
      slow:
        job: command
        every: 1d
        command: [sh, -c, "echo run >> #{@root}/slow.log; sleep 1"]
        cwd: #{@work}
      bad:
        job: command
        every: 1d
        command: [sh, -c, "echo broken >&2; exit 3"]
        cwd: #{@work}
    YAML
    results = concurrently(%w[bin/h-schedule run slow], %w[bin/h-schedule run slow])
    assert_equal [0, 0], results.map(&:last)
    assert_equal 1, results.count { |out, _| out.include?('completed exit 0') }
    assert_equal 1, results.count { |out, _| out.include?('skipped-overlap') && out.include?('occurrence held by run-') }
    assert_equal ["run\n"], File.readlines(File.join(@root, 'slow.log'))
    assert_equal [['completed', 0], ['skipped-overlap', nil]],
      db[:job_outcomes].where(definition: 'slow').order(:outcome).select_map(%i[outcome exit_code])
    assert_equal [['slow', 1, 'completed']], db[:job_claims].select_map(%i[definition attempt outcome])

    out, code = h('bin/h-schedule', 'run', 'bad')
    assert_equal 1, code
    row = db[:job_outcomes].where(definition: 'bad').first
    assert_equal ['failed', 3, 'exit 3'], row.values_at(:outcome, :exit_code, :detail)
    assert_equal "broken\n", File.read(row[:log_path])
    assert_includes out, "  log #{row[:log_path]}"
    assert_equal [1, ['bad', 'failed']], [db[:schedule_checkpoints].where(definition: 'bad').count,
      db[:schedule_checkpoints].where(definition: 'bad').get(%i[definition last_outcome])]

    out, code = h('bin/h-schedule', 'run', 'slow', '--scheduled')
    assert_equal ["slow: not enabled; nothing run\n", 0], [out, code]
  end

  def test_overlapping_reminder_checks_notify_each_occurrence_once_and_failures_stay_due
    h('bin/h-remind', 'every', 'Stretch', '30m')
    h('bin/h-remind', 'once', 'Submit', '202601011200', 'Glass')
    results = concurrently(%w[bin/h-remind check -v], %w[bin/h-remind check -v], extra: { 'NOTIFY_SLEEP' => '0.5' })
    assert_equal [0, 0], results.map(&:last)
    assert_equal ['-message Stretch -title Reminder -sound Basso', '-message Submit -title Reminder -sound Glass'],
      File.readlines(File.join(@root, 'notify.log'), chomp: true).sort
    assert_equal [['reminder:1', 'completed'], ['reminder:2', 'completed']],
      db[:job_claims].order(:definition).select_map(%i[definition outcome])
    assert_equal 2, db[:job_outcomes].where(outcome: 'completed').count
    assert_equal [true, false], db[:reminders].order(:id).select_map(:enabled)

    # A reload in a fresh process finds nothing due and claims nothing new.
    out, code = h('bin/h-remind', 'check', '-v')
    assert_equal ["Checked 1 enabled reminders, triggered 0\n1 completed one-time reminder(s) (use 'h remind clean' to remove)\n", 0], [out, code]
    assert_equal 2, db[:job_claims].count

    h('bin/h-remind', 'once', 'Call', '202601011300')
    FileUtils.touch(File.join(@root, 'notifier-broken'))
    out, code = h('bin/h-remind', 'check', '-v')
    assert_equal 1, code
    assert_match(/\ADelivery failed \(run-[0-9a-f-]+\): Call\n/, out)
    assert_equal [nil, true], db[:reminders].where(id: 3).get(%i[last_triggered enabled])
    assert_equal ['failed', 'notification delivery failed; retried on the next check'],
      db[:job_outcomes].where(definition: 'reminder:3').get(%i[outcome detail])
    File.delete(File.join(@root, 'notifier-broken'))
    out, code = h('bin/h-remind', 'check', '-v')
    assert_equal 0, code
    assert_includes out, "Triggered (one-time): Call\n"
    assert_equal [['reminder:3', '2026-01-01T13:00:00+00:00', 2, 'completed']],
      db[:job_claims].where(definition: 'reminder:3').select_map(%i[definition occurrence attempt outcome])
  end

  def test_queue_ticks_are_bounded_detached_and_settle_from_real_outcomes
    queue = File.join(@home, '.local/share/hiiro/queue')
    FileUtils.mkdir_p(File.join(queue, 'pending'))
    %w[a b c].each_with_index do |name, index|
      path = File.join(queue, 'pending', "job-#{name}.md")
      File.write(path, "Fix item #{name}\n")
      File.utime(Time.now - 60 + index, Time.now - 60 + index, path)
    end
    results = concurrently(%w[exe/h queue tick --max 1], %w[exe/h queue tick --max 1], extra: { 'OMP_SLEEP' => '1' })
    assert_equal [0, 0], results.map(&:last), results.inspect
    assert_equal 1, results.count { |out, _| out.include?('tick: launched 1, running 1 of 1') }, results.inspect
    assert_equal 1, results.count { |out, _| out.include?('tick: launched 0, running 1 of 1') }
    assert_equal ['job-b.md', 'job-c.md'], Dir.children(File.join(queue, 'pending')).sort
    deadline = Time.now + 10
    sleep 0.05 until File.exist?(File.join(@root, 'omp.log')) || Time.now > deadline
    assert_equal 1, File.readlines(File.join(@root, 'omp.log')).length
    assert_match(%r{\A-p @#{Regexp.escape(queue)}/running/job-a\.prompt\n\z}, File.read(File.join(@root, 'omp.log')))

    sleep 0.1 until File.exist?(File.join(queue, 'done/job-a.md')) || Time.now > deadline
    assert_equal "agent saw: Fix item a\n", File.read(File.join(queue, 'done/job-a.log'))

    out, code = h('exe/h', 'queue', 'tick', '--max', '1', extra: { 'OMP_EXIT' => '5' })
    assert_equal [0, true], [code, out.include?('Launched: job-b')]
    sleep 0.1 until File.exist?(File.join(queue, 'failed/job-b.md')) || Time.now > deadline + 10
    assert_equal ['job-b.log', 'job-b.md', 'job-b.meta'], Dir.children(File.join(queue, 'failed')).sort
    run_id = YAML.safe_load_file(File.join(queue, 'failed/job-b.meta'))['run_id']
    run = JSON.parse(File.read(File.join(@home, '.local/share/hiiro/runs', "#{run_id}.json")))
    assert_equal ['failed', { 'exit_code' => 5, 'signal' => nil }], run.values_at('state', 'outcome')
  end

  def test_loop_cycles_are_recorded_and_rendered_and_prompt_loops_need_an_agent
    FileUtils.mkdir_p([File.join(@home, 'ai/loops/prs'), File.join(@home, 'ai/loops/legacy')])
    File.write(File.join(@home, 'ai/loops/prs/config.yml'),
      { 'name' => 'prs', 'frequency' => '1d', 'prompt' => 'Summarize <PRs>', 'agent' => [File.join(@fix, 'summarize')] }.to_yaml)
    File.write(File.join(@home, 'ai/loops/legacy/config.yml'), { 'name' => 'legacy', 'frequency' => '10m', 'prompt' => 'keep me' }.to_yaml)
    fixture('summarize', "#!/bin/sh\necho \"summary for: $1\"\n")
    File.write(File.join(@home, 'ai/loops/prs/status.json'), '{"items":[{"title":"stale"}]}')

    out, code = h('bin/h-loop', 'run', 'legacy')
    assert_equal [1, "ERROR: loop-legacy: a prompt loop needs an explicit agent: argv (e.g. [claude, -p]) or a command: argv\n"], [code, out]
    out, code = h('bin/h-loop', 'run', 'prs')
    assert_equal 0, code
    assert_match(/\Aprs: completed exit 0 \(run-[0-9a-f-]+\): exit 0\n  log /, out)

    out, = h('bin/h-loop', 'status', 'prs')
    assert_includes out, "last completed cycle output ("
    assert_includes out, "  summary for: Summarize <PRs>\n"
    refute_includes out, 'stale'

    out, = h('bin/h-loop', 'ls')
    assert_match(/^legacy +10m +no +invalid +-\n  loop-legacy: a prompt loop needs an explicit agent/, out)
    assert_match(/^prs +1d +no +completed exit 0 /, out)

    h('bin/h-loop', 'render')
    html = File.read(File.join(@home, 'ai/home.html'))
    assert_includes html, '<pre>summary for: Summarize &lt;PRs&gt;</pre>'
    refute_includes html, 'http-equiv="refresh"'
    assert_equal({ 'name' => 'legacy', 'frequency' => '10m', 'prompt' => 'keep me' },
      YAML.safe_load_file(File.join(@home, 'ai/loops/legacy/config.yml')))
  end

  def test_claude_hook_setup_twice_and_reset_touch_only_owned_entries
    settings = File.join(@home, '.claude/settings.json')
    FileUtils.mkdir_p(File.dirname(settings))
    original = { 'model' => 'opus', 'hooks' => {
      'Stop' => [{ 'matcher' => '', 'hooks' => [{ 'type' => 'command', 'command' => 'say done' }] }],
      'PreToolUse' => [{ 'matcher' => 'Bash', 'hooks' => [{ 'type' => 'command', 'command' => 'guard.sh' }] }],
    } }
    File.write(settings, JSON.pretty_generate(original))
    notification = %q(MSG=$(cat | jq -r '.message // "Needs input"'); h notify push -t info "$MSG")
    stop = %q(h notify push -t success 'Work completed')

    out, code = h('bin/h-notify', 'claude', 'setup')
    assert_equal ["Notification: added\nStop: added\n#{settings}: updated\n", 0], [out, code]
    installed = JSON.parse(File.read(settings))
    out, = h('bin/h-notify', 'claude', 'setup')
    assert_equal "Notification: already present\nStop: already present\n#{settings}: unchanged\n", out
    assert_equal installed, JSON.parse(File.read(settings))
    assert_equal({ 'model' => 'opus', 'hooks' => {
      'Stop' => [original['hooks']['Stop'].first, { 'hooks' => [{ 'type' => 'command', 'command' => stop }] }],
      'PreToolUse' => original['hooks']['PreToolUse'],
      'Notification' => [{ 'hooks' => [{ 'type' => 'command', 'command' => notification }] }],
    } }, installed)

    out, = h('bin/h-notify', 'claude', 'reset_hooks')
    assert_equal "Notification: removed\nStop: removed\n#{settings}: updated\n", out
    assert_equal original, JSON.parse(File.read(settings))

    File.write(settings, '{ not json')
    out, code = h('bin/h-notify', 'claude', 'setup')
    assert_equal 1, code
    assert_match(/not valid JSON .*; left unchanged/, out)
    assert_equal '{ not json', File.read(settings)
  end
end
