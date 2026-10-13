require 'time'

class Hiiro
  # One node of a GitHub statusCheckRollup: a CheckRun or a StatusContext.
  # Retains the raw node so either provider's fields stay available. A policy
  # assessment (the ISC freeze state) is held beside raw, never written into it.
  class CheckContext
    FAILED_CONCLUSIONS = %w[FAILURE ERROR TIMED_OUT STALE STARTUP_FAILURE ACTION_REQUIRED].freeze
    PENDING_STATUSES   = %w[QUEUED IN_PROGRESS PENDING REQUESTED WAITING].freeze
    FAILED_STATES      = %w[FAILURE ERROR].freeze
    FREEZE_CONTEXT     = 'ISC code freeze'

    def self.from_node(hash, freeze_active: nil)
      raw = hash.is_a?(Hash) ? hash : {}
      context = new(raw)
      return context if freeze_active.nil? || !context.freeze?

      new(raw, assessed_state: freeze_active ? 'FAILURE' : 'SUCCESS')
    end

    attr_reader :raw, :assessed_state

    def initialize(raw, assessed_state: nil)
      @raw = raw
      @assessed_state = assessed_state
    end

    def assessed? = !assessed_state.nil?

    def kind
      case raw['__typename']
      when 'CheckRun'      then :check_run
      when 'StatusContext' then :status_context
      else                      :unknown
      end
    end

    def check_run?      = kind == :check_run
    def status_context? = kind == :status_context

    def name
      case kind
      when :check_run      then raw['name'] || raw['workflowName'] || '(unknown)'
      when :status_context then raw['context'] || '(unknown)'
      else                      raw['name'] || raw['context'] || '(unknown)'
      end
    end

    def url
      case kind
      when :check_run      then raw['detailsUrl']
      when :status_context then raw['targetUrl']
      else                      raw['detailsUrl'] || raw['targetUrl']
      end
    end

    # Upcased result the way `h pr status` tallies it:
    # CheckRun → conclusion, else status; StatusContext → state.
    def outcome
      value = check_run? ? (raw['conclusion'] || raw['status']) : state
      value.to_s.upcase
    end

    # GitHub's reported result, ignoring any policy assessment.
    def raw_outcome
      value = check_run? ? (raw['conclusion'] || raw['status']) : raw['state']
      value.to_s.upcase
    end

    def successful? = raw['conclusion'] == 'SUCCESS' || state == 'SUCCESS'
    def pending?    = PENDING_STATUSES.include?(raw['status']) || state == 'PENDING'
    def failed?     = FAILED_CONCLUSIONS.include?(raw['conclusion']) || FAILED_STATES.include?(state)
    def freeze?     = raw['__typename'] == 'StatusContext' && raw['context'] == FREEZE_CONTEXT

    private def state = assessed_state || raw['state']

    # Row shape stored by Hiiro::CheckRun.upsert_for_pr.
    def to_row(pr_number:)
      {
        pr_number:  pr_number,
        name:       raw['name']&.to_s,
        url:        (raw['url'] || raw['detailsUrl'])&.to_s,
        status:     raw['status']&.to_s,
        conclusion: raw['conclusion']&.to_s,
        updated_at: Time.now.iso8601,
      }
    end
  end

  # Counts over a PR's check contexts, plus whether the fetch was complete.
  # Built either from a raw rollup (fresh fetch) or from stored counts.
  class CheckSummary
    # nil when there is nothing to summarize (matches the old summarize_checks).
    # freeze_active: the ISC freeze policy input; nil leaves GitHub's state as reported.
    def self.from_rollup(rollup, truncated: false, freeze_active: nil)
      return nil unless rollup.is_a?(Array) && rollup.any?

      contexts = rollup.map { |node| CheckContext.from_node(node, freeze_active: freeze_active) }
      new(
        total:     contexts.length,
        success:   contexts.count(&:successful?),
        pending:   contexts.count(&:pending?),
        failed:    contexts.count(&:failed?),
        frozen:    contexts.count { |c| c.freeze? && c.failed? },
        truncated: truncated ? true : false,
        contexts:  contexts,
      )
    end

    # Rebuild from a stored { 'total','success','pending','failed','frozen'[, 'truncated'] } hash.
    # contexts: the stored raw rollup, when available, so names/urls can still be listed.
    def self.from_counts(hash, contexts: nil)
      return nil unless hash.is_a?(Hash)

      new(
        total:     hash['total'].to_i,
        success:   hash['success'].to_i,
        pending:   hash['pending'].to_i,
        failed:    hash['failed'].to_i,
        frozen:    hash['frozen'].to_i,
        truncated: hash['truncated'] ? true : false,
        contexts:  contexts.is_a?(Array) ? contexts.map { |node| CheckContext.from_node(node) } : [],
      )
    end

    attr_reader :total, :success, :pending, :failed, :frozen, :truncated, :contexts

    def initialize(total:, success:, pending:, failed:, frozen:, truncated: false, contexts: [])
      @total = total
      @success = success
      @pending = pending
      @failed = failed
      @frozen = frozen
      @truncated = truncated
      @contexts = contexts
    end

    def complete?    = !truncated
    def only_frozen? = failed > 0 && failed == frozen
    def any_pending? = pending > 0

    # The three filter predicates (h pr -r / -g / -p). A truncated list of
    # successes is never green: unfetched checks may be failing.
    def red?     = failed > 0
    def green?   = complete? && failed == 0 && pending == 0 && success > 0
    def pending? = pending > 0 && failed == 0

    # { 'SUCCESS' => 12, 'FAILURE' => 1 }; missing outcomes read as 0.
    def counts_by_outcome
      contexts.each_with_object(Hash.new(0)) { |c, h| h[c.outcome] += 1 }
    end

    def to_h
      h = { 'total' => total, 'success' => success, 'pending' => pending, 'failed' => failed, 'frozen' => frozen }
      h['truncated'] = true if truncated
      h
    end
  end
end
