require 'json'

class Hiiro
  # One implementation behind every single and bulk PR action. Targets are
  # resolved to qualified references before any parameter is read, the whole
  # request is validated before the first mutation, and each target reports
  # its own outcome.
  #
  #   targets = TargetSet(references: [team/one#42, team/two#5],
  #                       records: { team/one#42 => PinnedPr, team/two#5 => nil }, baseline: { 1 => ... })
  #   request = Request(name: 'merge', params: { 'strategy' => 'squash', 'delete_branch' => false }, targets:)
  #   outcome = Outcome(reference: team/two#5, ok: false, detail: 'gh failed (exit 1)')
  class PrActions
    TargetSet = Struct.new(:references, :records, :baseline, keyword_init: true)
    Request = Struct.new(:name, :params, :targets, keyword_init: true)
    Outcome = Struct.new(:reference, :ok, :detail, :interrupted, keyword_init: true)

    # params: the editable fields and their defaults. tracked: every target
    # must be a tracked record. bulk: the YAML-selection command name.
    Action = Struct.new(:name, :bulk, :params, :tracked, keyword_init: true)

    ACTIONS = [
      Action.new(name: 'open', bulk: 'mopen', params: {}),
      Action.new(name: 'view', params: {}),
      Action.new(name: 'diff', params: {}),
      Action.new(name: 'checkout', params: {}),
      Action.new(name: 'merge', bulk: 'mmerge', params: { 'strategy' => nil, 'delete_branch' => false }),
      Action.new(name: 'ready', bulk: 'mready', params: {}),
      Action.new(name: 'to-draft', bulk: 'mto-draft', params: {}),
      Action.new(name: 'comment', bulk: 'mcomment', params: { 'comment' => '' }),
      Action.new(name: 'sync', bulk: 'msync', params: {}),
      Action.new(name: 'untrack', bulk: 'mrm', params: {}, tracked: true),
      Action.new(name: 'fix', bulk: 'mfix', params: { 'run' => false }, tracked: true),
    ].to_h { |action| [action.name, action] }.freeze

    STRATEGIES = %w[merge squash rebase].freeze

    PARAM_HINTS = {
      'strategy' => 'merge | squash | rebase; blank for GitHub\'s default',
      'delete_branch' => 'true deletes the head branch after merging',
      'run' => 'true launches the queued jobs now; false only queues them',
    }.freeze

    attr_reader :manager

    # resolver: text -> qualified PullRequestReference, raising Hiiro::Error.
    # runner: CommandSpecification -> ProcessOutcome (foreground by default).
    # queue: -> Hiiro::Queue, built only when a fix is queued.
    def initialize(manager:, resolver:, runner: Hiiro::Shell.method(:foreground), queue: -> { Hiiro::Queue.current }, out: $stdout)
      @manager = manager
      @resolver = resolver
      @runner = runner
      @queue = queue
      @out = out
    end

    def self.bulk_names = ACTIONS.values.filter_map(&:bulk)
    def self.for_bulk(name) = ACTIONS.values.find { |action| action.bulk == name }

    def targets(texts, baseline: {})
      references = texts.map { |text| @resolver.call(text.to_s) }
      duplicates = references.tally.select { |_, count| count > 1 }.keys
      raise Hiiro::Error, "Duplicate PR: #{duplicates.join(', ')}" if duplicates.any?

      records = references.to_h { |ref| [ref, manager.find(ref)] }
      tracked = records.values.compact
      fresh = manager.edit_baseline(tracked.reject { |pr| baseline.key?(pr.id) })
      TargetSet.new(references: references, records: records, baseline: baseline.slice(*tracked.map(&:id)).merge(fresh))
    end

    # Targets from records already loaded, without resolving them again.
    def for_records(records)
      TargetSet.new(references: records.map(&:reference), records: records.to_h { |pr| [pr.reference, pr] },
                    baseline: manager.edit_baseline(records))
    end

    def request(name, texts, params = {}, baseline: {})
      Request.new(name: name, params: params, targets: targets(texts, baseline: baseline))
    end

    # Fills defaults and rejects unknown fields, bad values, and untracked
    # targets of tracked-only actions. Nothing has run when this raises.
    def validate!(request)
      action = ACTIONS[request.name] or raise Hiiro::Error, "Unknown PR action: #{request.name}"
      unknown = request.params.keys - action.params.keys
      raise Hiiro::Error, "#{action.name}: unknown field(s) #{unknown.join(', ')}" if unknown.any?

      params = action.params.merge(request.params)
      case action.name
      when 'merge'
        strategy = params['strategy']
        raise Hiiro::Error, "merge: strategy must be one of #{STRATEGIES.join(', ')} or blank" unless strategy.nil? || STRATEGIES.include?(strategy)
        raise Hiiro::Error, 'merge: delete_branch must be true or false' unless [true, false].include?(params['delete_branch'])
      when 'comment'
        raise Hiiro::Error, 'comment: empty comment' unless params['comment'].is_a?(String) && !params['comment'].strip.empty?
        params['comment'] = params['comment'].strip
      when 'fix'
        raise Hiiro::Error, 'fix: run must be true or false' unless [true, false].include?(params['run'])
      end
      if action.tracked
        untracked = request.targets.references.reject { |ref| request.targets.records[ref] }
        raise Hiiro::Error, "#{action.name}: not tracked: #{untracked.join(', ')}" if untracked.any?
      end
      request.params = params
      request
    end

    # Runs a validated request target by target. A target interrupted with
    # Ctrl-C stops the rest, which are reported as not attempted.
    def perform(request)
      validate!(request)
      @queued = []
      outcomes = []
      request.targets.references.each do |ref|
        outcome = if outcomes.last&.interrupted
          Outcome.new(reference: ref, ok: false, detail: 'not attempted (interrupted)', interrupted: true)
        else
          run_one(request, ref)
        end
        outcomes << outcome
        report_line(request, outcome)
      end
      summarize(request, outcomes)
      launch_queued(request.params['run']) if request.name == 'fix'
      outcomes
    end

    def report_line(request, outcome)
      mark = outcome.ok ? '✓' : '✗'
      @out.puts ["#{mark} #{outcome.reference} #{request.name}", outcome.detail].compact.join(': ')
    end

    def summarize(request, outcomes)
      return if outcomes.length < 2

      failed = outcomes.count { |outcome| !outcome.ok }
      @out.puts "#{request.name}: #{outcomes.length - failed} succeeded, #{failed} failed"
    end

    # The bulk YAML selection: returns [:ok, request], [:empty, nil],
    # [:cancelled, why], or [:invalid, why]. editor: text -> EditedDocument.
    def edit(action_name, records, editor:)
      action = ACTIONS.fetch(action_name)
      baseline = manager.edit_baseline(records)
      document = editor.call(template(action, records))
      return [:cancelled, 'editor exited unsuccessfully'] unless document.editor_succeeded?
      return [:cancelled, 'empty document'] if document.empty?
      return [:cancelled, 'document unchanged'] unless document.changed?
      return [:invalid, "invalid YAML: #{document.error.message}"] unless document.valid?

      data = document.parsed
      return [:invalid, 'expected a mapping with a prs: list'] unless data.is_a?(Hash) && data.key?('prs')
      return [:invalid, 'prs must be a list'] unless data['prs'].nil? || data['prs'].is_a?(Array)

      entries = Array(data['prs'])
      return [:empty, nil] if entries.empty?
      bad = entries.reject { |entry| entry.is_a?(String) || entry.is_a?(Integer) }
      return [:invalid, "not a PR reference: #{bad.first.inspect}"] if bad.any?

      [:ok, validate!(request(action.name, entries, data.reject { |key, _| key == 'prs' }, baseline: baseline))]
    rescue Hiiro::Error => e
      [:invalid, e.message]
    end

    def template(action, records)
      lines = [
        "# h pr #{action.bulk}: #{action.name} every PR left under prs.",
        '# Delete the PRs you do not want. Saving unchanged, saving an empty file,',
        '# or quitting the editor with an error cancels. `prs: []` selects nothing.',
        '',
        'prs:',
      ]
      lines += records.map { |pr| "- #{manager.reference_text(pr)}  # [#{pr.head_branch || '-'}] #{pr.title}" }
      action.params.each do |key, default|
        lines << ''
        if key == 'comment'
          lines << 'comment: |'
          lines << '  '
        else
          hint = PARAM_HINTS[key]
          lines << "#{key}:#{default.nil? ? '' : " #{default}"}#{hint ? "   # #{hint}" : ''}"
        end
      end
      lines.join("\n") + "\n"
    end

    private

    def run_one(request, ref)
      params = request.params
      record = request.targets.records[ref]
      case request.name
      when 'open'     then gh(ref, 'pr', 'view', ref.url, '--web')
      when 'view'     then gh(ref, 'pr', 'view', ref.url)
      when 'diff'     then gh(ref, 'pr', 'diff', ref.url)
      when 'checkout' then gh(ref, 'pr', 'checkout', ref.url)
      when 'ready'    then gh(ref, 'pr', 'ready', ref.url)
      when 'to-draft' then gh(ref, 'pr', 'ready', '--undo', ref.url)
      when 'comment'  then gh(ref, 'pr', 'comment', ref.url, '--body', params['comment'])
      when 'merge'
        flags = [("--#{params['strategy']}" if params['strategy']), ('--delete-branch' if params['delete_branch'])].compact
        gh(ref, 'pr', 'merge', ref.url, *flags)
      when 'sync'
        rebase = gh(ref, 'pr', 'update-branch', '--rebase', ref.url)
        return rebase if rebase.ok || rebase.interrupted

        merged = gh(ref, 'pr', 'update-branch', ref.url)
        merged.ok ? Outcome.new(reference: ref, ok: true, detail: "rebase #{rebase.detail}; merged the base branch instead") : merged
      when 'untrack' then untrack(ref, record, request.targets.baseline)
      when 'fix'     then queue_fix(ref, record)
      end
    rescue Hiiro::Error => e
      Outcome.new(reference: ref, ok: false, detail: e.message)
    end

    def gh(ref, *args)
      outcome = @runner.call(Hiiro::CommandSpecification.new('gh', *args))
      Outcome.new(reference: ref, ok: outcome.success?, detail: outcome.success? ? nil : "gh failed (#{outcome})",
                  interrupted: outcome.signal == 'INT')
    rescue SystemCallError => e
      Outcome.new(reference: ref, ok: false, detail: "gh could not start: #{e.message}")
    end

    def untrack(ref, record, baseline)
      raise Hiiro::Error, 'no longer tracked' unless manager.find(record)

      manager.remove([record.id], baseline: baseline.slice(record.id))
      Outcome.new(reference: ref, ok: true, detail: 'removed from tracking')
    end

    def queue_fix(ref, record)
      job = PrFixJob.for(record)
      added = @queue.call.add_with_frontmatter(job.content, name: job.name)
      raise Hiiro::Error, 'queue did not accept the job' unless added

      @queued << added[:name]
      Outcome.new(reference: ref, ok: true, detail: "queued #{added[:name]}")
    end

    def launch_queued(launch)
      return if @queued.empty?

      if launch
        @out.puts 'Launching...'
        @queued.each { |name| @queue.call.launch_task(name) }
      else
        @out.puts "Run 'h queue run' to start."
      end
    end
  end

  # The queue job for fixing one PR at its observed head revision. Shared by
  # `h pr fix`/`mfix` and the monitor's opt-in queueing.
  #
  #   { name: 'pr-fix-team-one-42-aaaaaaa',
  #     content: "---\npr: team/one#42\npr_url: ...\nhead_sha: aaaa...\ntask_name: work\n---\n/pr:fix https://...\n..." }
  class PrFixJob
    attr_reader :name, :content

    def self.for(record) = new(record)

    def initialize(record)
      ref = record.reference
      head = record.head_sha
      @name = ['pr-fix', ref.repo.owner, ref.repo.name, ref.number, head && head[0, 7]].compact.join('-')
      front = { 'pr' => ref.to_s, 'pr_url' => ref.url, 'head_sha' => head,
                'task_name' => record.task, 'tree_name' => record.worktree, 'session_name' => record.herdr_workspace }.compact
      @content = "---\n#{front.map { |key, value| "#{key}: #{value}" }.join("\n")}\n---\n#{body(record, ref, head)}"
    end

    private

    def body(record, ref, head)
      summary = record.check_summary
      failing = summary ? summary.contexts.select(&:failed?) : []
      lines = ["/pr:fix #{ref.url}", '', "PR: #{ref} #{ref.url}", "Head revision: #{head || 'unknown (never observed)'}"]
      lines << "Snapshot: #{record.freshness}#{record.fetched_at ? ", fetched #{record.fetched_at}" : ''}, " \
               "checks #{record.checks_complete? ? 'complete' : 'incomplete'}#{record.refresh_error ? " (#{record.refresh_error})" : ''}"
      if failing.empty?
        lines << 'Failing checks: none observed'
      else
        lines << 'Failing checks:'
        failing.each { |context| lines << "- #{context.name} #{context.outcome}#{context.url ? " #{context.url}" : ''}" }
      end
      lines.join("\n")
    end
  end
end
