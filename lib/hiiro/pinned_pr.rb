require 'sequel'

class Hiiro
  class PinnedPr < Sequel::Model(:prs)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:prs) do
        primary_key :id
        Integer :number
        String :title
        String :state
        String :url
        String :head_ref_name
        String :branch             # from old TrackedPr
        String :repo
        Integer :slot
        TrueClass :pinned          # true = pinned/monitored, false/nil = just tracked
        TrueClass :is_draft
        String :mergeable
        String :review_decision
        String :checks_json        # JSON: { total, success, pending, failed, frozen }
        String :check_runs_json    # JSON array of raw statusCheckRollup nodes
        String :reviews_json       # JSON: { approved, changes_requested, reviewers }
        String :task
        String :worktree
        String :herdr_workspace
        String :tmux_session
        String :tmux_json          # from old TrackedPr: JSON { session, window, pane }
        String :tags_json          # JSON array of strings
        TrueClass :assigned
        TrueClass :authored
        String :depends_on_json    # JSON array of 'owner/name#N'; a legacy integer stays until it is qualified
        String :last_checked       # last refresh attempt
        String :pinned_at
        String :created_at
        String :updated_at
        # Remote snapshot (written only by PinnedPRManager#refresh)
        String :head_sha
        String :fetched_at         # last successful observation, ISO 8601 UTC with microseconds
        TrueClass :checks_complete
        TrueClass :reviews_complete
        String :review_nodes_json  # JSON array of raw review nodes
        String :refresh_outcome    # fresh | stale | unknown
        String :refresh_error
        TrueClass :freeze_active   # ISC freeze policy input at the last observation; nil = not evaluated
      end
    end

    def self.migrate!(db)
      db.transaction(mode: :immediate) do
        columns = db.schema(:prs).map(&:first)
        workspace_added = !columns.include?(:herdr_workspace)
        integer_columns = %i[number slot]
        boolean_columns = %i[pinned is_draft assigned authored checks_complete reviews_complete freeze_active]
        string_columns = %i[title state url head_ref_name branch repo mergeable review_decision checks_json check_runs_json reviews_json task worktree herdr_workspace tmux_session tmux_json tags_json depends_on_json last_checked pinned_at created_at updated_at
                            head_sha fetched_at review_nodes_json refresh_outcome refresh_error]
        (integer_columns + boolean_columns + string_columns).each do |column|
          next if columns.include?(column)
          type = integer_columns.include?(column) ? Integer : (boolean_columns.include?(column) ? TrueClass : String)
          db.alter_table(:prs) { add_column column, type }
        end

        if workspace_added
          db[:prs].where(herdr_workspace: nil).exclude(tmux_session: nil)
            .update(herdr_workspace: Sequel[:tmux_session])
        end

        # A PR URL is trustworthy repository evidence; a row with neither stays unqualified.
        db[:prs].where(repo: nil).exclude(url: nil).select(:id, :url).all.each do |row|
          identity = Hiiro::PullRequestReference.from_url(row[:url])&.repo
          db[:prs].where(id: row[:id], repo: nil).update(repo: identity.path) if identity
        end
        qualify_legacy_dependencies!(db)
      end
    end

    # Legacy dependencies are bare PR numbers. One is qualified only when exactly
    # one tracked record has that number and it is in the depending PR's
    # repository; otherwise the integer is retained and reported.
    def self.qualify_legacy_dependencies!(db)
      rows = db[:prs].exclude(depends_on_json: nil).select(:id, :repo, :url, :depends_on_json).all
      rows.each do |row|
        deps = Hiiro::DB::JSON.load(row[:depends_on_json])
        next unless deps.is_a?(Array) && deps.any? { |dep| dep.is_a?(Integer) }

        owner_repo = Hiiro::RepositoryIdentity.parse(row[:repo] || row[:url])
        qualified = deps.map do |dep|
          next dep unless dep.is_a?(Integer) && owner_repo
          candidates = db[:prs].where(number: dep).select(:repo, :url).all.map { |c| Hiiro::RepositoryIdentity.parse(c[:repo] || c[:url]) }
          candidates == [owner_repo] ? Hiiro::PullRequestReference.new(number: dep, repo: owner_repo).to_s : dep
        end
        next if qualified == deps
        db[:prs].where(id: row[:id], depends_on_json: row[:depends_on_json]).update(depends_on_json: ::JSON.generate(qualified.uniq))
      end
    end

    # --- JSON virtual accessors ---

    def checks      = Hiiro::DB::JSON.load(checks_json)
    def check_runs  = Hiiro::DB::JSON.load(check_runs_json)
    def reviews     = Hiiro::DB::JSON.load(reviews_json)
    def review_nodes = Hiiro::DB::JSON.load(review_nodes_json)
    def tags        = Hiiro::DB::JSON.load(tags_json) || []
    def depends_on  = Hiiro::DB::JSON.load(depends_on_json)

    # Qualified dependency references, and the legacy integers that could not be qualified.
    def dependency_references = Array(depends_on).filter_map { |dep| dep.is_a?(String) ? Hiiro::PullRequestReference.qualified(dep) : nil }
    def unresolved_dependencies = Array(depends_on).select { |dep| dep.is_a?(Integer) }

    def checks=(v)     self.checks_json     = Hiiro::DB::JSON.dump(v) end
    def check_runs=(v) self.check_runs_json = Hiiro::DB::JSON.dump(v) end
    def reviews=(v)    self.reviews_json    = Hiiro::DB::JSON.dump(v) end
    def tags=(v)       self.tags_json       = Hiiro::DB::JSON.dump(v) end
    def depends_on=(v) self.depends_on_json = Hiiro::DB::JSON.dump(v) end

    # Backward-compat alias — PinnedPRManager and display code use head_branch
    def head_branch     = head_ref_name
    def head_branch=(v) self.head_ref_name = v end

    # --- Class methods ---

    def self.by_slot
      order(:slot).where(pinned: true)
    end

    # A qualified reference matches its own repository only. A bare number is
    # resolved against tracked records and must name exactly one.
    def self.find_by_reference(ref, pinned_only: true)
      scope = where(number: ref.number)
      scope = scope.where(pinned: true) if pinned_only
      matches = scope.all
      matches.select! { |pr| pr.reference.repo == ref.repo } if ref.repo
      if matches.length > 1
        raise Hiiro::Error, "Ambiguous PR ##{ref.number} (#{matches.map { |pr| pr.reference }.join(', ')}); use owner/name##{ref.number} or its URL"
      end
      matches.first
    end

    # Sync the check_runs table for this PR from the cached check_runs_json blob.
    def sync_check_runs
      runs = Hiiro::DB::JSON.load(check_runs_json)
      Hiiro::CheckRun.upsert_for_pr(id, runs) if id
    end

    # --- Instance methods ---

    # Convert back to a Hiiro::Git::Pr for API calls or display code that expects it.
    def to_git_pr
      Hiiro::Git::Pr.new(
        number:          number,
        title:           title,
        state:           state,
        url:             url,
        head_branch:     head_ref_name,
        repo:            repo,
        slot:            slot,
        is_draft:        is_draft,
        mergeable:       mergeable,
        review_decision: review_decision,
        checks:          checks,
        check_runs:      check_runs,
        reviews:         reviews,
        task:            task,
        worktree:        worktree,
        herdr_workspace: herdr_workspace,
        tags:            tags,
        assigned:        assigned,
        authored:        authored,
        depends_on:      depends_on,
        last_checked:    last_checked,
        pinned_at:       pinned_at,
        updated_at:      updated_at,
      )
    end


    # --- Predicates (mirroring Hiiro::Git::Pr) ---

    def open?        = state&.upcase == 'OPEN'
    def closed?      = state&.upcase == 'CLOSED'
    def merged?      = state&.upcase == 'MERGED'
    def draft?       = is_draft == true
    def conflicting? = mergeable == 'CONFLICTING'

    def reference = Hiiro::PullRequestReference.new(number: number, repo: Hiiro::RepositoryIdentity.parse(repo || url))

    # fresh: the last refresh observed GitHub; stale: it failed after an earlier
    # observation (kept as-is); unknown: nothing was ever observed.
    def freshness = refresh_outcome || 'unknown'
    def fresh?    = freshness == 'fresh'

    # Completeness of the stored observation. Rows observed before snapshots
    # existed only know whether their checks were truncated.
    def checks_complete?  = checks_complete.nil? ? !(checks || {})['truncated'] : checks_complete
    def reviews_complete? = reviews_complete == true

    # Derived assessment: raw contexts with the ISC freeze policy applied.
    # check_runs_json itself always holds GitHub's contexts unchanged.
    def check_summary
      Hiiro::CheckSummary.from_rollup(check_runs, truncated: !checks_complete?, freeze_active: freeze_active) ||
        (check_runs.nil? ? Hiiro::CheckSummary.from_counts(checks) : nil)
    end

    def red?     = check_summary&.red?
    def pending? = check_summary&.pending?

    # Merge-ready evidence: a fresh observation with every check and review fetched.
    def green? = fresh? && checks_complete? && reviews_complete? && check_summary&.green? == true

    def active?    = !merged? && !closed?
    def drafts?    = draft?
    def conflicts? = conflicting?

    def matches_filters?(opts, forced: [])
      state_active = Hiiro::Git::Pr::STATE_FILTER_KEYS.select { |k| forced.include?(k) || (opts.respond_to?(k) && opts.send(k)) }
      check_active = Hiiro::Git::Pr::CHECK_FILTER_KEYS.select { |k| forced.include?(k) || (opts.respond_to?(k) && opts.send(k)) }

      state_match = state_active.empty? || state_active.any? { |k| send(:"#{k}?") }
      check_match = check_active.empty? || check_active.any? { |k| send(:"#{k}?") }

      state_match && check_match
    end

    def to_s = "##{number}: #{title}"
  end
end
