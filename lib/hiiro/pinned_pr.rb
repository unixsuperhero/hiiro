require 'sequel'

class Hiiro
  class PinnedPr < Sequel::Model(:pinned_prs)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:pinned_prs) do
        primary_key :id
        Integer :number
        String :title
        String :state
        String :url
        String :head_ref_name
        String :repo
        Integer :slot
        TrueClass :is_draft
        String :mergeable
        String :review_decision
        String :checks_json        # JSON: { total, success, pending, failed, frozen }
        String :check_runs_json    # JSON array of raw statusCheckRollup nodes
        String :reviews_json       # JSON: { approved, changes_requested, reviewers }
        String :task
        String :worktree
        String :tmux_session
        String :tags_json          # JSON array of strings
        TrueClass :assigned
        TrueClass :authored
        String :depends_on_json    # JSON array of PR numbers
        String :last_checked
        String :pinned_at
        String :updated_at
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
      order(:slot)
    end

    def self.find_by_number(n)
      where(number: n).first
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
        tmux_session:    pr.tmux_session,
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
        tmux_session:    tmux_session,
        tags:            tags,
        assigned:        assigned,
        authored:        authored,
        depends_on:      depends_on,
        last_checked:    last_checked,
        pinned_at:       pinned_at,
        updated_at:      updated_at,
      )
    end

    # Serialize to string-keyed hash for YAML dual-write (mirrors Git::Pr#to_pinned_h).
    def to_pinned_h
      {
        'number'            => number,
        'title'             => title,
        'state'             => state,
        'url'               => url,
        'headRefName'       => head_ref_name,
        'repo'              => repo,
        'slot'              => slot,
        'is_draft'          => is_draft,
        'mergeable'         => mergeable,
        'review_decision'   => review_decision,
        'checks'            => checks,
        'statusCheckRollup' => check_runs,
        'reviews'           => reviews,
        'last_checked'      => last_checked,
        'pinned_at'         => pinned_at,
        'updated_at'        => updated_at,
        'task'              => task,
        'worktree'          => worktree,
        'tmux_session'      => tmux_session,
        'tags'              => (Array(tags).empty? ? nil : tags),
        'assigned'          => assigned,
        'authored'          => authored,
        'depends_on'        => (Array(depends_on).empty? ? nil : depends_on),
      }.compact
    end

    # --- Predicates (mirroring Hiiro::Git::Pr) ---

    def open?        = state&.upcase == 'OPEN'
    def closed?      = state&.upcase == 'CLOSED'
    def merged?      = state&.upcase == 'MERGED'
    def draft?       = is_draft == true
    def conflicting? = mergeable == 'CONFLICTING'

    def red?     = (c = checks) && c['failed'].to_i > 0
    def green?   = (c = checks) && c['failed'].to_i == 0 && c['pending'].to_i == 0 && c['success'].to_i > 0
    def pending? = (c = checks) && c['pending'].to_i > 0 && c['failed'].to_i == 0

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
