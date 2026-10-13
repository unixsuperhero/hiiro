require 'time'

class Hiiro
  # Continuous PR monitoring over the stored snapshots. Each cycle refreshes
  # the tracked open PRs through PinnedPRManager#refresh, observes each one,
  # and compares it with its checkpoints:
  #
  #   observation = { reference: team/one#42, head_sha: 'aaaa…', title: 'one', url: '…', draft: false,
  #                   checks: 'failing', review: 'approved', dependencies: 'waiting' }
  #   checkpoint  = { channel: 'checks', head_sha: 'aaaa…', state: 'pending', delivered_at: … }
  #   event       = { reference:, channel: 'checks', from: 'pending', to: 'failing', head_sha: 'aaaa…', baseline: false }
  #
  # 'unknown' (a stale, never-observed, or incomplete observation that shows
  # no failure) never produces an event, so it can never look like passing or
  # approval.
  class PrMonitor
    Observation = Struct.new(:reference, :head_sha, :title, :url, :draft, :checks, :review, :dependencies, :record, keyword_init: true)
    Event = Struct.new(:reference, :channel, :from, :to, :head_sha, :baseline, :observation, keyword_init: true)

    # Channels whose state belongs to one head revision. A review decision or
    # a dependency outlives a push, so a new head alone is not a new event there.
    HEAD_CHANNELS = %w[checks fix ready].freeze

    Options = Struct.new(:notify_status, :notify_approvals, :notify_dependencies, :notify_publishing,
                         :mark_ready, :queue_fixes, :tags, keyword_init: true) do
      def self.defaults = new(notify_status: true, notify_approvals: true, notify_dependencies: true,
                              notify_publishing: true, mark_ready: false, queue_fixes: false, tags: [])
    end

    def self.checks_state(pr)
      return 'unknown' unless pr.fresh? && pr.head_sha

      summary = pr.check_summary
      return 'failing' if summary&.red?
      return 'unknown' unless pr.checks_complete?
      return 'none' if summary.nil? || summary.total.zero?
      return 'pending' if summary.any_pending?

      summary.green? ? 'passing' : 'unknown'
    end

    def self.review_state(pr)
      return 'unknown' unless pr.fresh? && pr.reviews_complete?

      reviews = pr.reviews || {}
      case pr.review_decision
      when 'APPROVED' then 'approved'
      when 'CHANGES_REQUESTED' then 'changes_requested'
      when 'REVIEW_REQUIRED' then 'review_required'
      else
        if reviews['changes_requested'].to_i.positive? then 'changes_requested'
        elsif reviews['approved'].to_i.positive? then 'approved'
        else 'review_required'
        end
      end
    end

    # satisfied: every dependency is tracked and observed merged.
    def self.dependency_state(pr, tracked)
      refs = pr.dependency_references
      return 'none' if refs.empty? && pr.unresolved_dependencies.empty?
      return 'unknown' if pr.unresolved_dependencies.any?

      deps = refs.map { |ref| tracked.find { |row| row.reference == ref } }
      return 'unknown' if deps.any? { |dep| dep.nil? || dep.freshness == 'unknown' }

      deps.all?(&:merged?) ? 'satisfied' : 'waiting'
    end

    def self.observe(pr, tracked)
      Observation.new(reference: pr.reference, head_sha: pr.head_sha, title: pr.title, url: pr.url || pr.reference.url,
                      draft: pr.draft?, checks: checks_state(pr), review: review_state(pr),
                      dependencies: dependency_state(pr, tracked), record: pr)
    end

    # The one transition function: previous checkpoints (channel => {head_sha,
    # state}) against a new observation. A channel with no checkpoint yields a
    # baseline event; an unknown state yields nothing.
    def self.transitions(checkpoints, observation, channels)
      channels.filter_map do |channel, state|
        next if state == 'unknown'

        before = checkpoints[channel]
        changed = before.nil? || before.state != state ||
                  (HEAD_CHANNELS.include?(channel) && before.head_sha != observation.head_sha)
        next unless changed

        Event.new(reference: observation.reference, channel: channel, from: before&.state, to: state,
                  head_sha: observation.head_sha, baseline: before.nil?, observation: observation)
      end
    end

    attr_reader :manager, :options

    # notifier: args (the `h alert` grammar) -> true/false.
    # ready: reference -> ProcessOutcome for `gh pr ready`.
    def initialize(manager:, options: Options.defaults, notifier: Hiiro::Notification.method(:deliver),
                   queue: -> { Hiiro::Queue.current }, ready: nil, out: $stdout)
      @manager = manager
      @options = options
      @notifier = notifier
      @queue = queue
      @ready = ready || ->(ref) { Hiiro::Shell.foreground(Hiiro::CommandSpecification.new('gh', 'pr', 'ready', ref.url)) }
      @out = out
    end

    def channels_for(observation)
      channels = { 'checks' => observation.checks, 'review' => observation.review, 'dependencies' => observation.dependencies }
      channels.delete('dependencies') if observation.dependencies == 'none'
      channels['fix'] = observation.checks if options.queue_fixes
      channels['ready'] = observation.checks if options.mark_ready
      channels
    end

    # One refresh plus one pass over every tracked open PR. Returns the events
    # with what happened to each: :baseline, :recorded, :delivered, or :failed
    # (left undelivered, so the next cycle tries again).
    def cycle
      tracked = manager.load_pinned
      watched = tracked.select(&:active?)
      watched.select! { |pr| (Array(pr.tags) & options.tags).any? } if options.tags.any?
      report = manager.refresh(watched, force: true)
      report.incomplete.each { |pr, error| @out.puts "incomplete #{pr.reference}: #{error}" }
      report.failed.each { |pr, error| @out.puts "refresh failed #{pr.reference}: #{error}" }
      report.unqualified.each { |pr, error| @out.puts "not monitored id #{pr.id} #{pr.reference}: #{error}" }

      tracked = manager.load_pinned
      watched = tracked.select { |pr| watched.any? { |w| w.id == pr.id } && pr.reference.qualified? }
      watched.flat_map do |pr|
        observation = self.class.observe(pr, tracked)
        checkpoints = Hiiro::PrMonitorCheckpoint.for(observation.reference)
        self.class.transitions(checkpoints, observation, channels_for(observation)).map { |event| [event, handle(event)] }
      end
    end

    private

    def handle(event)
      result, detail = if event.baseline
        record(event, delivered: false, detail: 'baseline')
        [:baseline, 'baseline']
      else
        deliver(event)
      end
      @out.puts line(event, detail)
      result
    end

    def deliver(event)
      ok, detail = case event.channel
                   when 'checks'       then notify(event, options.notify_status, "PR checks #{event.to}")
                   when 'review'       then notify(event, options.notify_approvals && %w[approved changes_requested].include?(event.to), "PR #{event.to.tr('_', ' ')}")
                   when 'dependencies' then notify(event, options.notify_dependencies && event.to == 'satisfied', 'PR dependencies merged')
                   when 'fix'          then queue_fix(event)
                   when 'ready'        then mark_ready(event)
                   end
      return [:failed, 'failed; retried next cycle'] unless ok

      record(event, delivered: detail != 'recorded', detail: detail)
      [detail == 'recorded' ? :recorded : :delivered, detail]
    end

    # [true, 'recorded'] when the transition needs no effect.
    def notify(event, wanted, title)
      return [true, 'recorded'] unless wanted

      message = "#{event.reference}: #{event.observation.title}"
      message += " (#{event.head_sha[0, 7]})" if event.head_sha && event.channel == 'checks'
      delivered = @notifier.call(['-t', title, '-m', message, '-l', event.observation.url])
      [delivered, delivered ? 'notified' : nil]
    end

    def queue_fix(event)
      return [true, 'recorded'] unless event.to == 'failing'

      job = Hiiro::PrFixJob.for(event.observation.record)
      added = @queue.call.add_with_frontmatter(job.content, name: job.name)
      added ? [true, "queued #{added[:name]}"] : [false, nil]
    rescue Hiiro::Error, SystemCallError => e
      @out.puts "queue failed #{event.reference}: #{e.message}"
      [false, nil]
    end

    def mark_ready(event)
      return [true, 'recorded'] unless event.to == 'passing' && event.observation.draft

      if options.notify_publishing
        @notifier.call(['-t', 'PR marked ready', '-m', "#{event.reference}: #{event.observation.title}", '-l', event.observation.url])
      end
      outcome = @ready.call(event.reference)
      outcome.success? ? [true, 'marked ready'] : [false, nil]
    end

    def record(event, delivered:, detail:)
      Hiiro::PrMonitorCheckpoint.record!(event.reference, event.channel, head_sha: event.head_sha,
                                         state: event.to, delivered: delivered, detail: detail)
    end

    def line(event, detail)
      head = event.head_sha ? " at #{event.head_sha[0, 7]}" : ''
      change = event.baseline ? "baseline #{event.to}" : "#{event.from} → #{event.to}"
      "#{event.reference} #{event.channel} #{change}#{head}: #{detail}"
    end
  end
end
