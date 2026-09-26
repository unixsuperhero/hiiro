require 'yaml'

class Hiiro
  class Git
    class Pr
      PINNED_FILE = Hiiro::Config.path('pinned_prs.yml')
      FAILED_CONCLUSIONS = Hiiro::CheckContext::FAILED_CONCLUSIONS

      attr_accessor :number, :title, :state, :url, :head_branch, :base_branch,
                    :repo, :slot, :is_draft, :mergeable, :review_decision,
                    :checks, :check_runs, :reviews, :last_checked, :pinned_at, :updated_at,
                    :task, :worktree, :herdr_workspace, :tags, :assigned, :authored, :depends_on

      # Load all pinned PRs from YAML, returning an array of Pr instances.
      def self.pinned_prs
        return [] unless File.exist?(PINNED_FILE)
        prs = YAML.load_file(PINNED_FILE) || []
        prs.map { |h| from_pinned_hash(h) }
      rescue
        []
      end

      def self.is_link?(link)
        !Hiiro::PullRequestReference.from_url(link).nil?
      end

      def self.from_link(link)
        ref = Hiiro::PullRequestReference.from_url(link) or return nil
        new(number: ref.number_string, url: link, repo: ref.repo.path)
      end

      def self.from_number(number)
        ref = Hiiro::PullRequestReference.parse(number) or return nil
        new(number: ref.number_string)
      end

      def self.repo_from_url(url)
        Hiiro::PullRequestReference.from_url(url)&.repo&.path
      end

      # Build a Pr from a stored YAML hash. Handles both camelCase keys (legacy)
      # and snake_case keys. Falls back to computing checks from raw statusCheckRollup
      # if the summarized checks hash is missing (pre-refresh data).
      def self.from_pinned_hash(hash)
        raw_rollup = hash['statusCheckRollup']
        raw_rollup = nil unless raw_rollup.is_a?(Array) && raw_rollup.any?
        stored_checks = hash['checks']
        checks = stored_checks || (raw_rollup ? summarize_checks(raw_rollup) : nil)

        new(
          number:          hash['number'],
          title:           hash['title'],
          state:           hash['state'],
          url:             hash['url'],
          head_branch:     hash['headRefName'] || hash['head_branch'],
          base_branch:     hash['baseRefName'] || hash['base_branch'],
          repo:            hash['repo'],
          slot:            hash['slot'],
          is_draft:        hash.key?('is_draft') ? hash['is_draft'] : hash['isDraft'],
          mergeable:       hash['mergeable'],
          review_decision: hash['review_decision'] || hash['reviewDecision'],
          checks:          checks,
          check_runs:      raw_rollup,
          reviews:         hash['reviews'],
          last_checked:    hash['last_checked'],
          pinned_at:       hash['pinned_at'],
          updated_at:      hash['updated_at'],
          task:            hash['task'],
          worktree:        hash['worktree'],
          herdr_workspace: hash['herdr_workspace'] || hash['tmux_session'],
          tags:            hash['tags'],
          assigned:        hash['assigned'],
          authored:        hash['authored'],
          depends_on:      hash['depends_on'],
        )
      end

      # Build a Pr from GitHub API JSON (gh pr view --json or GraphQL).
      # Stores both the raw check run nodes (check_runs) and the summary (checks).
      def self.from_gh_json(data)
        rollup   = data['statusCheckRollup']
        rollup   = rollup.is_a?(Array) && rollup.any? ? rollup : nil
        reviews  = data['reviews'].is_a?(Array) ? data['reviews'] : data.dig('reviews', 'nodes')

        new(
          number:          data['number'],
          title:           data['title'],
          state:           data['state'],
          url:             data['url'],
          head_branch:     data['headRefName'],
          base_branch:     data['baseRefName'],
          repo:            data['repo'] || repo_from_url(data['url']),
          is_draft:        data['isDraft'],
          mergeable:       data['mergeable'],
          review_decision: data['reviewDecision'],
          checks:          rollup  ? summarize_checks(rollup)   : nil,
          check_runs:      rollup,
          reviews:         reviews ? summarize_reviews(reviews) : nil,
        )
      end

      def self.list(state: 'open', limit: 30)
        output = `gh pr list --state #{state} --limit #{limit} --json number,title,state,url,headRefName,baseRefName 2>/dev/null`
        return [] if output.empty?

        require 'json'
        JSON.parse(output).map { |data| from_gh_json(data) }
      rescue
        []
      end

      def self.create(title:, body: nil, base: nil, draft: false)
        args = ['gh', 'pr', 'create', '--title', title]
        args += ['--body', body] if body
        args += ['--base', base] if base
        args << '--draft' if draft
        system(*args)
      end

      # Summarizes raw statusCheckRollup contexts into { total, success, pending, failed, frozen }.
      # frozen = number of failed contexts that are specifically the ISC code freeze check.
      # truncated: true is added when pagination couldn't retrieve all checks.
      def self.summarize_checks(rollup, truncated: false)
        Hiiro::CheckSummary.from_rollup(rollup, truncated: truncated)&.to_h
      end

      # Summarizes raw review nodes into { approved, changes_requested, commented, reviewers }.
      def self.summarize_reviews(reviews)
        return nil unless reviews.is_a?(Array) && !reviews.empty?

        latest_by_author = {}
        reviews.each do |review|
          author = review.dig('author', 'login')
          next unless author
          state = review['state']
          next unless %w[APPROVED CHANGES_REQUESTED COMMENTED].include?(state)
          latest_by_author[author] = state
        end

        approved          = latest_by_author.values.count { |s| s == 'APPROVED' }
        changes_requested = latest_by_author.values.count { |s| s == 'CHANGES_REQUESTED' }
        commented         = latest_by_author.values.count { |s| s == 'COMMENTED' }

        { 'approved' => approved, 'changes_requested' => changes_requested,
          'commented' => commented, 'reviewers' => latest_by_author }
      end

      def self.current
        output = `gh pr view --json number,title,state,url,headRefName,baseRefName 2>/dev/null`
        return nil if output.empty?

        require 'json'
        from_gh_json(JSON.parse(output))
      rescue
        nil
      end

      def initialize(number:, title: nil, state: nil, url: nil, head_branch: nil, base_branch: nil,
                     repo: nil, slot: nil, is_draft: nil, mergeable: nil, review_decision: nil,
                     checks: nil, check_runs: nil, reviews: nil, last_checked: nil,
                     pinned_at: nil, updated_at: nil,
                     task: nil, worktree: nil, herdr_workspace: nil, tmux_session: nil,
                     tags: nil, assigned: nil, authored: nil,
                     depends_on: nil)
        @number          = number
        @title           = title
        @state           = state
        @url             = url
        @head_branch     = head_branch
        @base_branch     = base_branch
        @repo            = repo
        @slot            = slot
        @is_draft        = is_draft
        @mergeable       = mergeable
        @review_decision = review_decision
        @checks          = checks
        @check_runs      = check_runs
        @reviews         = reviews
        @last_checked    = last_checked
        @pinned_at       = pinned_at
        @updated_at      = updated_at
        @task            = task
        @worktree        = worktree
        @herdr_workspace = herdr_workspace || tmux_session
        @tags            = tags
        @assigned        = assigned
        @authored        = authored
        @depends_on      = depends_on ? Array(depends_on).map(&:to_i) : nil
      end

      # Compatibility accessors for older callers and serialized records.
      def tmux_session = herdr_workspace
      def tmux_session=(value)
        self.herdr_workspace = value
      end

      def open?        = state&.upcase == 'OPEN'
      def closed?      = state&.upcase == 'CLOSED'
      def merged?      = state&.upcase == 'MERGED'
      def draft?       = is_draft == true
      def conflicting? = mergeable == 'CONFLICTING'

      # Checks as a CheckSummary (nil when no checks are known).
      def check_summary
        Hiiro::CheckSummary.from_counts(checks, contexts: check_runs)
      end

      def reference
        Hiiro::PullRequestReference.new(number: number, repo: Hiiro::RepositoryIdentity.parse(repo || url))
      end

      # Check-status predicates
      def red?     = check_summary&.red?
      def green?   = check_summary&.green?
      def pending? = check_summary&.pending?

      # Aliases matching filter option names
      def active?    = !merged? && !closed?
      def drafts?    = draft?
      def conflicts? = conflicting?

      # Filter dimensions. Flags within each group OR together; groups AND together.
      # e.g. -o -g → (active?) AND (green?), -o -r -g → (active?) AND (red? OR green?)
      STATE_FILTER_KEYS = %i[active merged drafts conflicts].freeze
      CHECK_FILTER_KEYS = %i[red green pending].freeze

      # Returns true if this PR satisfies the filter options set in opts.
      # forced: injects additional filter keys as if the user had set them.
      def matches_filters?(opts, forced: [])
        state_active = STATE_FILTER_KEYS.select { |k| forced.include?(k) || (opts.respond_to?(k) && opts.send(k)) }
        check_active = CHECK_FILTER_KEYS.select { |k| forced.include?(k) || (opts.respond_to?(k) && opts.send(k)) }

        state_match = state_active.empty? || state_active.any? { |k| send(:"#{k}?") }
        check_match = check_active.empty? || check_active.any? { |k| send(:"#{k}?") }

        state_match && check_match
      end

      def view     = system('gh', 'pr', 'view', number.to_s)
      def checkout = system('gh', 'pr', 'checkout', number.to_s)

      def merge(method: nil, delete_branch: true)
        args = ['gh', 'pr', 'merge', number.to_s]
        args << "--#{method}" if method
        args << '--delete-branch' if delete_branch
        system(*args)
      end

      def close  = system('gh', 'pr', 'close', number.to_s)
      def reopen = system('gh', 'pr', 'reopen', number.to_s)

      # Serialize back to string-keyed hash for YAML storage.
      def to_pinned_h
        {
          'number'              => number,
          'title'               => title,
          'state'               => state,
          'url'                 => url,
          'headRefName'         => head_branch,
          'repo'                => repo,
          'slot'                => slot,
          'is_draft'            => is_draft,
          'mergeable'           => mergeable,
          'review_decision'     => review_decision,
          'checks'              => checks,
          'statusCheckRollup'   => check_runs,
          'reviews'             => reviews,
          'last_checked'        => last_checked,
          'pinned_at'           => pinned_at,
          'updated_at'          => updated_at,
          'task'                => task,
          'worktree'            => worktree,
          'herdr_workspace'     => herdr_workspace,
          'tags'                => (Array(tags).empty? ? nil : tags),
          'assigned'            => assigned,
          'authored'            => authored,
          'depends_on'          => (Array(depends_on).empty? ? nil : depends_on),
        }.compact
      end

      def to_s = "##{number}: #{title}"

      def to_h
        {
          number:          number,
          title:           title,
          state:           state,
          url:             url,
          head_branch:     head_branch,
          base_branch:     base_branch,
          repo:            repo,
          slot:            slot,
          is_draft:        is_draft,
          mergeable:       mergeable,
          review_decision: review_decision,
          checks:          checks,
          reviews:         reviews,
          last_checked:    last_checked,
          pinned_at:       pinned_at,
          updated_at:      updated_at,
          task:            task,
          worktree:        worktree,
          herdr_workspace: herdr_workspace,
          tags:            tags,
          assigned:        assigned,
          authored:        authored,
        }.compact
      end
    end
  end
end
