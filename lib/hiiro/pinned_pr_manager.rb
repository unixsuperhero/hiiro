require 'json'
require 'time'

class Hiiro
  class PinnedPRManager

    def self.add_resolvers(hiiro)
      pm = new
      hiiro.add_resolver(:pr,
        -> {
          pinned = pm.load_pinned
          if pinned.empty?
            STDERR.puts "No tracked PRs. Use a PR number or 'h pr track' to track PRs."
            nil
          else
            lines = pinned.each_with_index.each_with_object({}) do |(pr, idx), h|
              h[pm.strip_ansi(pm.display_pinned(pr, idx, oneline: true))] = pm.reference_text(pr)
            end
            hiiro.fuzzyfind_from_map(lines)
          end
        }
      ) do |ref|
        value = (hiiro.pins.get(ref.to_s) || ref).to_s
        if (pr = pm.find(value))
          pm.reference_text(pr)
        elsif value.match?(/\A\d+\z/) && (pr = pm.load_pinned.find { |p| p.slot == value.to_i })
          pm.reference_text(pr)
        else
          value
        end
      end
    end


    def add_options(opts)
      opts.flag(:red,       short: 'r', desc: 'filter: failing checks')
      opts.flag(:green,     short: 'g', desc: 'filter: passing checks')
      opts.flag(:conflicts, short: 'c', desc: 'filter: merge conflicts')
      opts.flag(:drafts,    short: 'D', desc: 'filter: draft PRs')
      opts.flag(:pending,   short: 'p', desc: 'filter: pending checks')
      opts.flag(:merged,    short: 'm', desc: 'filter: merged PRs')
      opts.flag(:active,    short: 'o', desc: 'filter: open (non-merged) PRs')
      opts.flag(:numbers,   short: 'n', desc: 'output PR numbers only (no #)')
      opts.option(:tag,     short: 't', desc: 'filter by tag (OR when multiple; AND with flag filters)', multi: true)
    end

    def load_pinned = Hiiro::PinnedPr.by_slot.all

    def reference_text(pr) = pr.reference.url || pr.number.to_s

    # PinnedPr | PullRequestReference | object with number + repo/url | text
    # (URL, owner/name#N, #N, N). A bare number must match one tracked PR.
    def find(ref, pinned_only: true)
      if ref.is_a?(Hiiro::PinnedPr)
        scope = Hiiro::PinnedPr.where(id: ref.id)
        scope = scope.where(pinned: true) if pinned_only
        return scope.first
      end
      reference = if ref.is_a?(Hiiro::PullRequestReference)
        ref
      elsif ref.respond_to?(:number) && ref.respond_to?(:repo)
        Hiiro::PullRequestReference.new(number: ref.number, repo: Hiiro::RepositoryIdentity.parse(ref.repo || ref.url))
      else
        Hiiro::PullRequestReference.parse(ref)
      end
      reference && Hiiro::PinnedPr.find_by_reference(reference, pinned_only: pinned_only)
    end

    # Starts tracking a qualified reference with local preferences only; the
    # remote snapshot arrives through #refresh. Returns [record, :created |
    # :promoted | :already].
    def track(reference, task: nil, worktree: nil, herdr_workspace: nil)
      raise Hiiro::Error, "Cannot track #{reference}: no repository" unless reference.qualified?

      Hiiro::DB.connection.transaction(mode: :immediate) do
        existing = find(reference, pinned_only: false)
        if existing&.pinned
          [existing, :already]
        elsif existing
          slot = existing.slot || Hiiro::PinnedPr.max(:slot).to_i + 1
          Hiiro::PinnedPr.where(id: existing.id).update(pinned: true, slot: slot, pinned_at: existing.pinned_at || Time.now.iso8601)
          [existing.refresh, :promoted]
        else
          record = Hiiro::PinnedPr.create(
            number: reference.number, repo: reference.repo.path, url: reference.url, pinned: true,
            slot: Hiiro::PinnedPr.max(:slot).to_i + 1, pinned_at: Time.now.iso8601, created_at: Time.now.iso8601,
            task: task, worktree: worktree, herdr_workspace: herdr_workspace,
          )
          [record, :created]
        end
      end
    end

    def unpin(ref)
      Hiiro::DB.connection.transaction(mode: :immediate) do
        pr = find(ref)
        next false unless pr
        Hiiro::CheckRun.where(pr_id: pr.id).delete
        Hiiro::Tag.where(taggable_type: 'PinnedPr', taggable_id: pr.id.to_s).delete
        pr.delete
        true
      end
    end

    def pinned?(ref) = !find(ref).nil?

    def change_tags(ref, add: [], remove: [], clear: false)
      mutate_array(ref, :tags, add: add, remove: remove, clear: clear)
    end

    # add/remove: qualified PullRequestReferences, stored as 'owner/name#N'.
    # remove also accepts legacy integers that were never qualified.
    def change_dependencies(ref, add: [], remove: [], clear: false)
      added = add.map do |dep|
        raise Hiiro::Error, "Dependency #{dep} has no repository; use owner/name#N or its URL" unless dep.qualified?
        dep.to_s
      end
      removed = remove.map { |dep| dep.is_a?(Integer) ? dep : dep.to_s }
      mutate_array(ref, :depends_on, add: added, remove: removed, clear: clear)
    end

    def mutate_array(ref, field, add:, remove:, clear:)
      Hiiro::DB.connection.transaction(mode: :immediate) do
        pr = find(ref)
        raise Hiiro::Error, 'PR is no longer tracked' unless pr
        values = clear ? [] : ((Array(pr.public_send(field)) + add).uniq - remove)
        pr.public_send("#{field}=", values.empty? ? nil : values)
        pr.save_changes
        pr
      end
    end

    EDIT_FIELDS = %w[tags depends_on task worktree herdr_workspace assigned authored].freeze
    # Local preferences a deletion must not silently discard. Remote snapshot
    # columns and check rows belong to #refresh and never block a deletion.
    LOCAL_COLUMNS = (EDIT_FIELDS.map { |field| :"#{field}_json" if %w[tags depends_on].include?(field) } +
                     EDIT_FIELDS.map(&:to_sym) + %i[pinned slot branch tmux_json]).compact.freeze

    def edit_rows(prs)
      prs.map { |pr| { 'id' => pr.id }.merge(EDIT_FIELDS.to_h { |field| [field, pr.public_send(field)] }) }
    end

    def edit_baseline(prs)
      prs.to_h do |pr|
        [pr.id, { record: pr,
                  tags: Hiiro::Tag.where(taggable_type: 'PinnedPr', taggable_id: pr.id.to_s).order(:id).all.map(&:values) }]
      end
    end

    def local_values(pr) = pr.values.slice(*LOCAL_COLUMNS)

    def apply_edits(rows, baseline:)
      raise Hiiro::Error, 'Expected a list of PR records' unless rows.is_a?(Array)
      originals = baseline.transform_values { |entry| entry.fetch(:record) }
      ids = rows.map do |row|
        raise Hiiro::Error, 'Each PR needs its original integer id' unless row.is_a?(Hash) && row['id'].is_a?(Integer) && originals.key?(row['id'])
        raise Hiiro::Error, 'Unknown PR edit field' unless (row.keys - ['id'] - EDIT_FIELDS).empty?
        value = row['tags']
        raise Hiiro::Error, 'Invalid tags' unless value.nil? || (value.is_a?(Array) && value.all? { |v| v.is_a?(String) })
        value = row['depends_on']
        legacy = Array(originals.fetch(row['id']).depends_on).select { |dep| dep.is_a?(Integer) }
        valid = value.nil? || (value.is_a?(Array) && value.all? { |v| (v.is_a?(String) && Hiiro::PullRequestReference.qualified(v)&.to_s == v) || legacy.include?(v) })
        raise Hiiro::Error, 'Invalid depends_on: use owner/name#N entries' unless valid
        %w[task worktree herdr_workspace].each do |field|
          raise Hiiro::Error, "Invalid #{field}" unless row[field].nil? || row[field].is_a?(String)
        end
        %w[assigned authored].each do |field|
          raise Hiiro::Error, "Invalid #{field}" unless [nil, true, false].include?(row[field])
        end
        row['id']
      end
      raise Hiiro::Error, 'Duplicate PR id' unless ids.uniq == ids
      Hiiro::DB.connection.transaction(mode: :immediate) do
        rows.each do |row|
          before = originals.fetch(row['id'])
          changes = row.reject { |field, value| field == 'id' || value == before.public_send(field) }
          next if changes.empty?
          current = find(before)
          raise Hiiro::Error, "PR id #{before.id} was removed" unless current
          changes.each do |field, value|
            actual = current.public_send(field)
            raise Hiiro::Error, "Conflict on PR id #{before.id}: #{field}" unless actual == before.public_send(field) || actual == value
            current.public_send("#{field}=", value)
          end
          current.save_changes
        end
        remove(originals.keys - ids, baseline: baseline)
      end
    end

    # Untracks the given ids, refusing any whose local preferences or tags
    # changed after the baseline was read; already-removed ids are skipped.
    def remove(ids, baseline:)
      Hiiro::DB.connection.transaction(mode: :immediate) do
        ids.each do |id|
          before = baseline.fetch(id).fetch(:record)
          current = find(before)
          next unless current
          unchanged = local_values(current) == local_values(before) && edit_baseline([current]).fetch(id)[:tags] == baseline.fetch(id)[:tags]
          raise Hiiro::Error, "Conflict deleting PR id #{id}" unless unchanged
          unpin(current)
        end
      end
    end

    # Qualifies a PR argument: URL or owner/name#N as given; a bare number
    # through gh's current repository; nil through the current-branch resolver.
    def lookup_reference(text = nil)
      return Hiiro::Git::Pr.current.reference if text.nil?

      ref = Hiiro::PullRequestReference.qualified(text)
      return ref if ref
      raise Hiiro::Error, "Not a PR reference: #{text}" unless text.to_s.strip.match?(/\A#?\d+\z/)

      data = gh_json('pr', 'view', text.to_s.strip.delete_prefix('#'), '--json', 'number,url')
      ref = data.is_a?(Hash) && Hiiro::PullRequestReference.from_url(data['url'])
      ref || raise(Hiiro::Error, "PR #{text} not found in the current repository")
    end

    def fetch_current_branch_pr
      Hiiro::Git::Pr.current
    rescue Hiiro::Error
      nil
    end

    def fetch_my_prs = fetch_pr_list('--author', '@me')
    def fetch_assigned_prs = fetch_pr_list('--assignee', '@me')

    def fetch_my_and_assigned_prs
      authored_prs = fetch_my_prs
      assigned_prs = fetch_assigned_prs

      authored = authored_prs.map(&:reference).to_set
      assigned_prs.each { |pr| pr.assigned = true unless authored.include?(pr.reference) }
      authored_prs.each { |pr| pr.authored = true }

      (authored_prs + assigned_prs).uniq(&:reference)
    end

    def needs_refresh?(pr, force: false)
      return true if force
      return true unless pr.last_checked

      last_check_time = Time.parse(pr.last_checked) rescue nil
      return true unless last_check_time

      # Refresh if last check was more than 2 minutes ago
      (Time.now - last_check_time) > 120
    end

    # The ISC freeze policy input: true while a freeze window is open, false
    # outside one, nil when `isc` cannot answer (GitHub's state then stands).
    def code_freeze_active?
      return @code_freeze_active if defined?(@code_freeze_active)

      result = Hiiro::Shell.run3('isc', 'codefreeze', 'list')
      return @code_freeze_active = nil unless result.success?

      now = Time.now
      @code_freeze_active = result.stdout.lines.drop(1).any? do |line|
        parts = line.strip.split(/\s{2,}/)
        next false if parts.length < 2

        start_time = Time.parse(parts[0]) rescue nil
        end_time   = Time.parse(parts[1]) rescue nil
        next false unless start_time && end_time

        now >= start_time && now <= end_time
      end
    rescue SystemCallError
      @code_freeze_active = nil
    end

    def fetcher = @fetcher ||= Hiiro::PrSnapshot::Fetcher.new

    # Outcome lists of one refresh: each entry is [record, message or nil].
    RefreshReport = Struct.new(:fresh, :incomplete, :failed, :unqualified, keyword_init: true) do
      def attempted? = (fresh + incomplete + failed + unqualified).any?
    end

    # The one refresh path for single and bulk updates: qualified active
    # records are fetched per repository, and each result is applied to its
    # row by a targeted update of remote columns only.
    def refresh(prs, force: false)
      report = RefreshReport.new(fresh: [], incomplete: [], failed: [], unqualified: [])
      targets = prs.select { |pr| pr.active? && needs_refresh?(pr, force: force) }
      qualified, report.unqualified = targets.partition { |pr| pr.reference.qualified? }
      report.unqualified.map! { |pr| [pr, 'no repository; track it again by URL'] }
      return report if qualified.empty?

      started_at = Time.now.utc.iso8601(6)
      results = fetcher.fetch(qualified.map(&:reference))
      qualified.each do |pr|
        result = results.fetch(pr.reference)
        if result.is_a?(Hiiro::PrSnapshot)
          # false: untracked meanwhile, or a newer observation already landed
          next unless apply_snapshot(pr, result)
          (result.complete? ? report.fresh : report.incomplete) << [pr, result.error]
        else
          record_failure(pr, result.error, started_at)
          report.failed << [pr, result.error]
        end
      end
      report
    end

    # Writes one observation unless the row is gone or already holds a newer
    # one; returns whether it wrote. Local columns (tags, task, dependencies,
    # monitoring) are never in the update.
    def apply_snapshot(pr, snapshot)
      fields = snapshot.fields.to_h { |key, value| [Hiiro::PrSnapshot::FIELDS.fetch(key), value] }
      fields.reject! { |key, value| value.nil? && %i[title state url head_ref_name].include?(key) }
      checks = snapshot.checks.nodes
      reviews = snapshot.reviews.nodes
      values = fields.merge(
        head_sha: snapshot.head_sha, fetched_at: snapshot.fetched_at,
        checks_complete: snapshot.checks.complete, reviews_complete: snapshot.reviews.complete,
        check_runs_json: Hiiro::DB::JSON.dump(checks),
        checks_json: Hiiro::DB::JSON.dump(Hiiro::CheckSummary.from_rollup(checks, truncated: !snapshot.checks.complete)&.to_h),
        review_nodes_json: Hiiro::DB::JSON.dump(reviews),
        reviews_json: Hiiro::DB::JSON.dump(Hiiro::Git::Pr.summarize_reviews(reviews)),
        refresh_outcome: 'fresh', refresh_error: snapshot.error,
        freeze_active: code_freeze_active?, last_checked: Time.now.iso8601,
      )
      Hiiro::DB.connection.transaction(mode: :immediate) do
        scope = Hiiro::PinnedPr.where(id: pr.id).where(Sequel.|({ fetched_at: nil }, Sequel[:fetched_at] < snapshot.fetched_at))
        written = scope.update(values) == 1
        Hiiro::CheckRun.upsert_for_pr(pr.id, checks) if written
        written
      end
    end

    # Keeps the last observation and marks it stale (or unknown when there is
    # none), unless another refresh observed the PR after this one started.
    def record_failure(pr, error, started_at)
      Hiiro::PinnedPr.where(id: pr.id).where(Sequel.|({ fetched_at: nil }, Sequel[:fetched_at] <= started_at)).update(
        refresh_outcome: Sequel.case([[Sequel.expr(fetched_at: nil), 'unknown']], 'stale'),
        refresh_error: error, last_checked: Time.now.iso8601,
      )
    end

    def display_pinned(pr, idx = nil, widths: {}, oneline: false)
      slot_w  = widths[:slot]  || 1
      succ_w  = widths[:succ]  || 1
      total_w = widths[:total] || 1
      as_w    = widths[:as]    || 1
      crs_w   = widths[:crs]   || 1

      slot_num = (pr.slot || (idx ? idx + 1 : 1)).to_s
      num    = "#{slot_num.rjust(slot_w)}."
      indent = " " * (slot_w + 2)

      check_emoji, checks_count_str =
        if (s = pr.check_summary)
          emoji = if s.red? && s.any_pending? then s.only_frozen? ? "⏳❄️" : "⏳❌"
                  elsif s.red?                then s.only_frozen? ? "　❄️" : "　❌"
                  elsif s.any_pending?        then "⏳　"
                  elsif !s.complete?          then "　❓"
                  else                             "　✅"
                  end
          [emoji, "#{s.success.to_s.rjust(succ_w)}/#{s.total.to_s.rjust(total_w)}"]
        else
          ["", nil]
        end

      state_label = case pr.state
      when 'MERGED' then 'M'
      when 'CLOSED' then 'X'
      else pr.draft? ? 'd' : 'o'
      end

      bracket_parts = [state_label, check_emoji, checks_count_str].reject { |p| p.nil? || p.empty? }
      state_icon = "[#{bracket_parts.join(' ')}]"

      r = pr.reviews || {}
      as  = r['approved'].to_i
      crs = r['changes_requested'].to_i

      as_val  = as  > 0 ? as.to_s  : '-'
      crs_val = crs > 0 ? crs.to_s : '-'
      as_colored  = as  > 0 ? "\e[30;102m#{as_val}\e[0m"  : as_val
      crs_colored = crs > 0 ? "\e[30;103m#{crs_val}\e[0m" : crs_val
      as_pad  = " " * [as_w  - as_val.length,  0].max
      crs_pad = " " * [crs_w - crs_val.length, 0].max
      conflict_str = pr.conflicting? ? " \e[30;101mC\e[0m" : ""
      reviews_str = "#{as_pad}#{as_colored}a/#{crs_pad}#{crs_colored}cr#{conflict_str}"

      tags = Array(pr.tags)
      tags_str = tags.any? ? tags.map { |t| "\e[30;104m#{t}\e[0m" }.join(' ') : nil

      branch_str = pr.head_branch ? " \e[90m#{pr.head_branch}\e[0m" : ""
      title_str = "\e[1m#{pr.title}\e[0m"
      line1 = "#{num} #{pr.reference} #{state_icon} #{reviews_str}#{branch_str}#{freshness_label(pr)}"
      line2 = "#{indent}#{title_str}"
      line3 = pr.url ? "#{indent}#{pr.url}" : nil
      line4 = tags_str ? "#{indent}#{tags_str}" : nil
      line5 = "#{indent}#{snapshot_line(pr)}"

      if oneline
        "#{line1} #{title_str}#{tags_str ? "  #{tags_str}" : ""}"
      else
        [line1, line2, line3, line4, line5].compact.join("\n")
      end
    end

    # '' for a fresh complete observation; otherwise why it is not evidence.
    def freshness_label(pr)
      case pr.freshness
      when 'stale'   then " \e[33mstale\e[0m"
      when 'unknown' then " \e[90munknown\e[0m"
      else (pr.checks_complete? && pr.reviews_complete?) ? '' : " \e[33mincomplete\e[0m"
      end
    end

    def snapshot_line(pr)
      parts = ["snapshot #{pr.freshness}"]
      parts << "head #{pr.head_sha[0, 7]}" if pr.head_sha
      parts << "fetched #{pr.fetched_at}" if pr.fetched_at
      parts << "checks #{pr.checks_complete? ? 'complete' : 'incomplete'}" if pr.fetched_at
      parts << "reviews #{pr.reviews_complete? ? 'complete' : 'incomplete'}" if pr.fetched_at
      parts << pr.refresh_error if pr.refresh_error
      parts.join(' · ')
    end

    def filter_active?(opts)
      all_keys = Hiiro::Git::Pr::STATE_FILTER_KEYS + Hiiro::Git::Pr::CHECK_FILTER_KEYS
      all_keys.any? { |f| opts.respond_to?(f) && opts.send(f) } ||
        (opts.respond_to?(:tag) && Array(opts.tag).any?)
    end

    def apply_filters(prs, opts, forced: [])
      results = prs.select { |pr| pr.matches_filters?(opts, forced: forced) }

      tag_filter = Array(opts.respond_to?(:tag) ? opts.tag : nil).map(&:to_s).reject(&:empty?)
      unless tag_filter.empty?
        results = results.select { |pr| (Array(pr.tags) & tag_filter).any? }
      end

      results
    end

    def display_detailed(pr, idx = nil)
      lines = []
      num = idx ? "#{idx + 1}." : ""

      state_str = case pr.state
      when 'MERGED' then 'MERGED'
      when 'CLOSED' then 'CLOSED'
      else pr.draft? ? 'DRAFT' : 'OPEN'
      end

      lines << "#{num} #{pr.reference} - #{pr.title}"
      lines << "   State: #{state_str}"
      lines << "   Branch: #{pr.head_branch}" if pr.head_branch
      lines << "   URL: #{pr.url}" if pr.url

      if (s = pr.check_summary)
        check_status = if s.red?             then "FAILING (#{s.success}/#{s.total} passed, #{s.failed} failed)"
                       elsif s.any_pending? then "PENDING (#{s.success}/#{s.total} passed, #{s.pending} pending)"
                       else                      "PASSING (#{s.success}/#{s.total})"
                       end
        lines << "   Checks: #{check_status}"
      else
        lines << "   Checks: (none)"
      end

      if pr.reviews
        r = pr.reviews
        review_parts = []
        review_parts << "#{r['approved']} approved" if r['approved'] > 0
        review_parts << "#{r['changes_requested']} requesting changes" if r['changes_requested'] > 0
        review_parts << "#{r['commented']} commented" if r['commented'] > 0

        if review_parts.any?
          lines << "   Reviews: #{review_parts.join(', ')}"
          if r['reviewers'] && !r['reviewers'].empty?
            r['reviewers'].each do |author, state|
              icon = case state
              when 'APPROVED' then '+'
              when 'CHANGES_REQUESTED' then '-'
              else '?'
              end
              lines << "      #{icon} #{author}: #{state.downcase.gsub('_', ' ')}"
            end
          end
        else
          lines << "   Reviews: (none)"
        end
      else
        lines << "   Reviews: (not fetched)"
      end

      lines << "   Mergeable: #{pr.mergeable}" if pr.mergeable

      lines.join("\n")
    end

    def strip_ansi(str)
      str.gsub(/\e\[[0-9;]*m/, '')
    end

    def display_check_runs(pr, indent: "   ")
      contexts = pr.check_summary&.contexts || []
      contexts.each do |ctx|
        emoji = case ctx.kind
                when :check_run      then check_run_emoji(ctx.raw['conclusion'], ctx.raw['status'])
                when :status_context then status_context_emoji(ctx.outcome)
                else '?'
                end
        line = "#{indent}#{emoji}  #{ctx.name}"
        line += "  (freeze policy: #{ctx.outcome}; GitHub: #{ctx.raw_outcome})" if ctx.assessed?
        line += "\n#{indent}   #{ctx.url}" if ctx.url
        puts line
      end
      puts "#{indent}(incomplete: #{pr.refresh_error || 'not every check was fetched'})" if pr.fetched_at && !pr.checks_complete?
    end

    private

    def gh_json(*args)
      result = Hiiro::Shell.run3('gh', *args)
      result.success? ? JSON.parse(result.stdout) : nil
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def fetch_pr_list(*filter)
      data = gh_json('pr', 'list', *filter, '--state', 'open', '--json', 'number,title,headRefName,url')
      data.is_a?(Array) ? data.map { |pr| Hiiro::Git::Pr.from_gh_json(pr) } : []
    end

    def check_run_emoji(conclusion, status)
      return "⏳" if %w[QUEUED IN_PROGRESS PENDING REQUESTED WAITING].include?(status) && conclusion.nil?
      case conclusion
      when 'SUCCESS'          then "✅"
      when 'FAILURE', 'ERROR' then "❌"
      when 'TIMED_OUT'        then "⏰"
      when 'CANCELLED'        then "🚫"
      when 'SKIPPED'          then "⏭ "
      when 'NEUTRAL'          then "⚪"
      when 'STARTUP_FAILURE'  then "💥"
      when 'ACTION_REQUIRED'  then "⚠️ "
      else                         "⏳"
      end
    end

    def status_context_emoji(state)
      case state
      when 'SUCCESS'          then "✅"
      when 'FAILURE', 'ERROR' then "❌"
      when 'PENDING'          then "⏳"
      else                         "❓"
      end
    end
  end
end
