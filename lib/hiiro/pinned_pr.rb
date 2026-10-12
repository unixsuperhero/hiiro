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
        String :depends_on_json    # JSON array of PR numbers
        String :last_checked
        String :pinned_at
        String :created_at
        String :updated_at
      end
    end

    def self.migrate!(db)
      db.transaction(mode: :immediate) do
        columns = db.schema(:prs).map(&:first)
        workspace_added = !columns.include?(:herdr_workspace)
        integer_columns = %i[number slot]
        boolean_columns = %i[pinned is_draft assigned authored]
        string_columns = %i[title state url head_ref_name branch repo mergeable review_decision checks_json check_runs_json reviews_json task worktree herdr_workspace tmux_session tmux_json tags_json depends_on_json last_checked pinned_at created_at updated_at]
        (integer_columns + boolean_columns + string_columns).each do |column|
          next if columns.include?(column)
          type = integer_columns.include?(column) ? Integer : (boolean_columns.include?(column) ? TrueClass : String)
          db.alter_table(:prs) { add_column column, type }
        end

        if workspace_added
          db[:prs].where(herdr_workspace: nil).exclude(tmux_session: nil)
            .update(herdr_workspace: Sequel[:tmux_session])
        end
      end
    end

    # --- JSON virtual accessors ---

    def checks      = Hiiro::DB::JSON.load(checks_json)
    def check_runs  = Hiiro::DB::JSON.load(check_runs_json)
    def reviews     = Hiiro::DB::JSON.load(reviews_json)
    def tags        = Hiiro::DB::JSON.load(tags_json) || []
    def depends_on  = Hiiro::DB::JSON.load(depends_on_json)

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

    def self.find_by_number(n)
      find_by_reference(Hiiro::PullRequestReference.new(number: n))
    end

    def self.find_by_reference(ref, pinned_only: true)
      scope = where(number: ref.number)
      scope = scope.where(pinned: true) if pinned_only
      matches = scope.all
      matches.select! { |pr| pr.reference.repo == ref.repo } if ref.repo
      raise Hiiro::Error, "Ambiguous PR ##{ref.number}; use its GitHub URL" if matches.length > 1
      matches.first
    end

    # Sync the check_runs table for this PR from the cached check_runs_json blob.
    def sync_check_runs
      runs = Hiiro::DB::JSON.load(check_runs_json)
      Hiiro::CheckRun.upsert_for_pr(id, runs) if id
    end

    # Build an in-memory PinnedPr from a Hiiro::Git::Pr (does NOT save).
    def self.from_git_pr(pr)
      new(
        number:          pr.number,
        title:           pr.title,
        state:           pr.state,
        url:             pr.url,
        head_ref_name:   pr.head_branch,
        repo:            pr.repo,
        slot:            pr.slot,
        pinned:          true,
        is_draft:        pr.is_draft,
        mergeable:       pr.mergeable,
        review_decision: pr.review_decision,
        checks_json:     Hiiro::DB::JSON.dump(pr.checks),
        check_runs_json: Hiiro::DB::JSON.dump(pr.check_runs),
        reviews_json:    Hiiro::DB::JSON.dump(pr.reviews),
        tags_json:       Hiiro::DB::JSON.dump(pr.tags),
        depends_on_json: Hiiro::DB::JSON.dump(pr.depends_on),
        task:            pr.task,
        worktree:        pr.worktree,
        herdr_workspace: pr.herdr_workspace,
        assigned:        pr.assigned,
        authored:        pr.authored,
        last_checked:    pr.last_checked,
        pinned_at:       pr.pinned_at,
        updated_at:      pr.updated_at,
      )
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

    def check_summary = Hiiro::CheckSummary.from_counts(checks, contexts: check_runs)
    def reference     = Hiiro::PullRequestReference.new(number: number, repo: Hiiro::RepositoryIdentity.parse(repo || url))

    def red?     = check_summary&.red?
    def green?   = check_summary&.green?
    def pending? = check_summary&.pending?

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
