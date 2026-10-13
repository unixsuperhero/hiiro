require 'sequel'
require 'json'
require 'time'
require 'fileutils'

class Hiiro
  # One worker's hold on one occurrence of recurring work. The unique
  # (definition, occurrence) pair is what makes overlapping workers safe: the
  # first insert wins, and a later worker either sees the holder alive
  # (skipped-overlap), finished, or gone (stale-owner, then re-claimed).
  #
  #   { definition: 'reminder:3', occurrence: '2026-10-13T12:00:00Z', run_id: 'run-…', attempt: 1,
  #     claimant: '{"pid":4242,"started":"Tue Oct 13 12:00:00 2026"}', claimed_at: '…', settled_at: nil, outcome: nil }
  class JobClaim < Sequel::Model(:job_claims)
    def self.create_table!(db)
      db.create_table?(:job_claims) do
        primary_key :id
        String :definition, null: false
        String :occurrence, null: false
        String :run_id, null: false
        Integer :attempt, null: false, default: 1
        String :claimant
        String :claimed_at, null: false
        String :settled_at
        String :outcome
        unique %i[definition occurrence]
      end
    end

    def claimant_identity = claimant && OwnedRun::ProcessIdentity.from_h(JSON.parse(claimant))
    def settled? = !settled_at.nil?

    Hiiro::DB.register(self)
  end

  # What happened to one run of recurring work, written once by the worker that
  # observed it (or by the next worker, for an owner that disappeared).
  #
  #   { run_id: 'run-…', definition: 'nightly', occurrence: '2026-10-13T02:30 local', attempt: 1,
  #     context: { trigger: 'launchd', cwd: '/work', command: 'backup --quick' },
  #     started_at: '…', finished_at: '…', outcome: 'failed', exit_code: 3, signal: nil,
  #     detail: 'exit 3', log_path: '~/.local/share/hiiro/jobs/nightly/run-….log',
  #     artifacts: [{ path: '/work/out/report.txt', bytes: 120 }], notification: 'delivered' }
  class JobOutcome < Sequel::Model(:job_outcomes)
    OUTCOMES = %w[completed failed interrupted startup-failed stale-owner skipped-overlap].freeze

    def self.create_table!(db)
      db.create_table?(:job_outcomes) do
        primary_key :id
        String :run_id, null: false, unique: true
        String :definition, null: false
        String :occurrence
        Integer :attempt
        String :context_json
        String :started_at
        String :finished_at, null: false
        String :outcome, null: false
        Integer :exit_code
        String :signal
        String :detail
        String :log_path
        String :artifacts_json
        String :notification
      end
    end

    def self.record!(**fields)
      raise ArgumentError, "Unknown outcome #{fields[:outcome]}" unless OUTCOMES.include?(fields[:outcome])

      context = fields.delete(:context)
      artifacts = fields.delete(:artifacts)
      values = fields.merge(context_json: context && JSON.generate(context), artifacts_json: artifacts && JSON.generate(artifacts))
      db.transaction(mode: :immediate) { where(run_id: values[:run_id]).first || create(values) }
    end

    def self.recent(limit: 200, definition: nil)
      rows = order(Sequel.desc(:finished_at), Sequel.desc(:id))
      rows = rows.where(Sequel.like(:definition, "#{definition}%")) if definition
      rows.limit(limit).all
    end

    def context = context_json ? JSON.parse(context_json) : {}
    def artifacts = artifacts_json ? JSON.parse(artifacts_json) : []
    def completed? = outcome == 'completed'

    def status_text
      code = signal ? "signal #{signal}" : (exit_code && "exit #{exit_code}")
      [outcome, code].compact.join(' ')
    end

    Hiiro::DB.register(self)
  end

  # Claims, runs, and records recurring work. Work runs either in-process
  # (perform: a reminder's notification) or as an owned child process
  # (execute: a schedule's command), and both end in one JobOutcome row.
  module Job
    RETRYABLE = %w[failed interrupted startup-failed stale-owner].freeze

    module_function

    def log_dir = @log_dir || File.join(Dir.home, '.local/share/hiiro/jobs')
    def log_dir=(value)
      @log_dir = value
    end
    def store = @store ||= OwnedRun::Store.default
    def store=(value)
      @store = value
    end

    def stamp(time) = time.utc.iso8601

    # => [:claimed, claim] | [:held, claim] | [:done, claim] | [:bounded, nil]
    def claim(definition, occurrence, run_id:, max_concurrent: nil, now: Time.now)
      JobClaim.db.transaction(mode: :immediate) do
        JobClaim.where(definition: definition, settled_at: nil).all.each { |held| reconcile(held, now: now) }
        existing = JobClaim.first(definition: definition, occurrence: occurrence)
        next [:held, existing] if existing && !existing.settled?
        next [:done, existing] if existing && !RETRYABLE.include?(existing.outcome)

        running = JobClaim.where(definition: definition, settled_at: nil).count
        next [:bounded, nil] if max_concurrent && running >= max_concurrent

        identity = OwnedRun::ProcessIdentity.of(Process.pid)
        values = { run_id: run_id, claimant: identity && JSON.generate(identity.to_h), claimed_at: stamp(now),
                   settled_at: nil, outcome: nil }
        if existing
          existing.update(values.merge(attempt: existing.attempt + 1))
          [:claimed, existing]
        else
          [:claimed, JobClaim.create(values.merge(definition: definition, occurrence: occurrence, attempt: 1))]
        end
      end
    end

    # An unsettled claim whose claimant and run are both gone is settled here:
    # with the run's real outcome when the supervisor recorded one, else stale-owner.
    def reconcile(held, now: Time.now)
      return if live?(held)

      run = store.find(held.run_id)
      if run&.finished?
        settle(held, outcome_for(run), finished_at: now, run: run, detail: "recorded after its worker exited")
      else
        store.update(run.id) { |record| record.fail('stale owner') if record.active? } if run
        settle(held, 'stale-owner', finished_at: now, run: run,
          detail: "claimant #{held.claimant_identity&.pid || '?'} exited before recording an outcome")
      end
    end

    def live?(held)
      return true if held.claimant_identity&.alive?

      run = store.find(held.run_id)
      run&.active? && run.process&.alive?
    end

    def settle(held, outcome, finished_at:, run: nil, detail: nil, **fields)
      started = run&.times&.[]('started') || held.claimed_at
      JobOutcome.record!(run_id: held.run_id, definition: held.definition, occurrence: held.occurrence,
        attempt: held.attempt, started_at: started, finished_at: stamp(finished_at), outcome: outcome,
        exit_code: run&.outcome&.exit_code, signal: run&.outcome&.signal, detail: detail, **fields)
      held.update(settled_at: stamp(finished_at), outcome: outcome)
    end

    def outcome_for(run, interrupted: false)
      return 'startup-failed' unless run.process
      return 'interrupted' if interrupted || run.outcome&.signal

      run.state == 'completed' ? 'completed' : 'failed'
    end

    def skipped(definition, occurrence, run_id:, reason:, context:, now:)
      JobOutcome.record!(run_id: run_id, definition: definition, occurrence: occurrence, context: context,
        started_at: stamp(now), finished_at: stamp(now), outcome: 'skipped-overlap', detail: reason)
    end

    def skip_reason(status, held, max_concurrent)
      status == :held ? "occurrence held by #{held.run_id}" : "#{max_concurrent} already running"
    end

    # In-process work. The block returns [outcome, detail]; nil when the
    # occurrence was already completed by another worker.
    def perform(definition, occurrence, context: {}, now: Time.now)
      run_id = OwnedRun.new_id
      status, held = claim(definition, occurrence, run_id: run_id, now: now)
      return nil if status == :done
      return skipped(definition, occurrence, run_id: run_id, reason: skip_reason(status, held, nil), context: context, now: now) unless status == :claimed

      begin
        outcome, detail = yield
      rescue Exception => e # recorded, then re-raised
        error = e
        outcome = e.is_a?(SignalException) ? 'interrupted' : 'failed'
        detail = "#{e.class}: #{e.message}"
      end
      record = JobOutcome.record!(run_id: run_id, definition: definition, occurrence: occurrence, attempt: held.attempt,
        context: context, started_at: stamp(now), finished_at: stamp(Time.now), outcome: outcome, detail: detail)
      held.update(settled_at: stamp(Time.now), outcome: outcome)
      raise error if error

      record
    end

    # Child-process work under the owned-run supervisor, bounded by timeout.
    # The log keeps stdout and stderr; it is deleted after a completed run
    # unless keep_log. Returns the JobOutcome, or nil when already done.
    def execute(definition, occurrence, command:, timeout:, max_concurrent: 1, context: {}, keep_log: false,
                artifacts: [], now: Time.now)
      run_id = OwnedRun.new_id
      context = context.merge('cwd' => command.cwd, 'command' => command.preview).compact
      status, held = claim(definition, occurrence, run_id: run_id, max_concurrent: max_concurrent, now: now)
      return nil if status == :done
      unless status == :claimed
        return skipped(definition, occurrence, run_id: run_id, reason: skip_reason(status, held, max_concurrent),
          context: context, now: now)
      end

      log = File.join(log_dir, definition.tr('/:', '__'), "#{run_id}.log")
      FileUtils.mkdir_p(File.dirname(log))
      request = OwnedRun::LaunchRequest.new(id: run_id, owner: { 'kind' => 'job', 'definition' => definition,
        'occurrence' => occurrence }, command: command, placement: { 'kind' => 'job', 'log' => log }, process_group: true)
      store.create(OwnedRun.allocate(request))
      interrupted, detail = supervise(run_id, log, timeout)
      run = store.find(run_id)
      outcome = outcome_for(run, interrupted: interrupted)
      detail ||= run.error || run.outcome&.to_s
      found = artifacts.filter_map do |path|
        full = File.expand_path(path, command.cwd || Dir.pwd)
        { 'path' => full, 'bytes' => File.size(full) } if File.file?(full)
      end
      kept = !(outcome == 'completed' && !keep_log)
      FileUtils.rm_f(log) unless kept
      settle(held, outcome, finished_at: Time.now, run: run, detail: detail, context: context,
        log_path: (log if kept), artifacts: found)
      JobOutcome.first(run_id: run_id)
    end

    # Waits for the supervisor; on timeout or a stop signal to this worker the
    # child's process group gets TERM, then KILL after a grace period.
    def supervise(run_id, log, timeout)
      supervisor = Process.spawn(*OwnedRun::Supervisor.argv(store, run_id), in: File::NULL, out: [log, 'a'], err: [:child, :out])
      stop = nil
      previous = %w[TERM INT HUP].to_h { |sig| [sig, trap(sig) { stop = "worker received SIG#{sig}" }] }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        break if Process.wait(supervisor, Process::WNOHANG)

        stop ||= "timed out after #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        if stop
          terminate(store.find(run_id))
          Process.wait(supervisor)
          return [true, stop]
        end
        sleep 0.05
      end
      [false, nil]
    ensure
      previous&.each { |sig, handler| trap(sig, handler || 'DEFAULT') }
    end

    def terminate(run, grace: 5)
      process = run&.process
      return unless process&.alive?

      Process.kill('TERM', -process.pid)
      deadline = Time.now + grace
      sleep 0.05 while process.alive? && Time.now < deadline
      Process.kill('KILL', -process.pid) if process.alive?
    rescue Errno::ESRCH
      nil
    end
  end
end
