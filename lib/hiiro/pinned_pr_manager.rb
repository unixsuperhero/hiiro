require 'yaml'
require 'json'
require 'time'
require 'fileutils'

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
              h[pm.strip_ansi(pm.display_pinned(pr, idx, oneline: true))] = pr.number.to_s
            end
            hiiro.fuzzyfind_from_map(lines)
          end
        }
      ) do |ref|
        if (pin_value = hiiro.pins.get(ref.to_s))
          pin_value
        else
          pinned = pm.load_pinned
          if pinned.any? { |pr| pr.number.to_s == ref.to_s }
            ref.to_s
          elsif ref.to_s =~ /^\d+$/ && ref.to_i > 0
            slot = ref.to_i
            by_slot = pinned.find { |p| p.slot.to_i == slot }
            if by_slot
              by_slot.number.to_s
            elsif slot - 1 < pinned.length
              # Fall back to 1-based index for unslotted data
              pinned[slot - 1].number.to_s
            else
              ref.to_s
            end
          else
            ref.to_s
          end
        end
      end
    end

    def initialize(fs: Hiiro::Effects::Filesystem.new)
      @fs = fs
      ensure_file
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

    def pr_repo(pr)
      pr.repo || Hiiro::Git::Pr.repo_from_url(pr.url)
    end

    def ensure_file
      return unless Hiiro::DB.dual_write?
      dir = File.dirname(Hiiro::Git::Pr::PINNED_FILE)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      @fs.write(Hiiro::Git::Pr::PINNED_FILE, [].to_yaml) unless File.exist?(Hiiro::Git::Pr::PINNED_FILE)
    end

    def load_pinned
      prs = Hiiro::PinnedPr.by_slot.all
      if prs.any? { |p| p.slot.nil? }
        next_slot = prs.map { |p| p.slot.to_i }.max.to_i
        prs.each do |p|
          next if p.slot
          next_slot += 1
          p.update(slot: next_slot)
        end
      end
      prs
    end

    def save_pinned(prs)
      Hiiro::DB.connection.transaction do
        Hiiro::PinnedPr.where(pinned: true).delete
        prs.each do |pr|
          pinned = pr.is_a?(Hiiro::PinnedPr) ? pr : Hiiro::PinnedPr.from_git_pr(pr)
          attrs  = pinned.to_hash.reject { |k, _| k == :id }
          attrs[:pinned] = true
          saved = Hiiro::PinnedPr.new(attrs)
          saved.save
          saved.sync_check_runs
        end
      end
      # Dual-write YAML for backward compat
      if Hiiro::DB.dual_write?
        ensure_file
        @fs.write(Hiiro::Git::Pr::PINNED_FILE, prs.map(&:to_pinned_h).to_yaml)
      end
    end

    def pin(pr)
      pr.repo ||= Hiiro::Git::Pr.repo_from_url(pr.url)

      existing = Hiiro::PinnedPr.find_by_number(pr.number)

      if existing
        updates = {
          updated_at: Time.now.iso8601,
        }
        updates[:title]           = pr.title           unless pr.title.nil?
        updates[:state]           = pr.state           unless pr.state.nil?
        updates[:url]             = pr.url             unless pr.url.nil?
        updates[:head_ref_name]   = pr.head_branch     unless pr.head_branch.nil?
        updates[:repo]            = pr.repo            unless pr.repo.nil?
        updates[:is_draft]        = pr.is_draft        unless pr.is_draft.nil?
        updates[:mergeable]       = pr.mergeable       unless pr.mergeable.nil?
        updates[:review_decision] = pr.review_decision unless pr.review_decision.nil?
        updates[:check_runs_json] = Hiiro::DB::JSON.dump(pr.check_runs) unless pr.check_runs.nil?
        updates[:checks_json]     = Hiiro::DB::JSON.dump(pr.checks)     unless pr.checks.nil?
        updates[:reviews_json]    = Hiiro::DB::JSON.dump(pr.reviews)    unless pr.reviews.nil?
        updates[:task]            = pr.task            unless pr.task.nil?
        updates[:worktree]        = pr.worktree        unless pr.worktree.nil?
        updates[:tmux_session]    = pr.tmux_session    unless pr.tmux_session.nil?
        updates[:tags_json]       = Hiiro::DB::JSON.dump(pr.tags) unless pr.tags.nil?
        updates[:assigned]        = pr.assigned        unless pr.assigned.nil?
        updates[:authored]        = pr.authored        unless pr.authored.nil?
        existing.update(updates)
        existing.sync_check_runs if updates.key?(:check_runs_json)
      else
        pinned = pr.is_a?(Hiiro::PinnedPr) ? pr : Hiiro::PinnedPr.from_git_pr(pr)
        pinned.slot      = Hiiro::PinnedPr.max(:slot).to_i + 1
        pinned.pinned_at = Time.now.iso8601
        pinned.pinned    = true
        pinned.save
        pinned.sync_check_runs
      end

      # Dual-write YAML
      if Hiiro::DB.dual_write?
        ensure_file
        all_prs = Hiiro::PinnedPr.by_slot.all
        @fs.write(Hiiro::Git::Pr::PINNED_FILE, all_prs.map(&:to_pinned_h).to_yaml)
      end

      pr
    end

    def unpin(pr_number)
      removed = Hiiro::PinnedPr.where(number: pr_number.to_i).delete
      # Dual-write YAML
      if Hiiro::DB.dual_write?
        ensure_file
        all_prs = Hiiro::PinnedPr.by_slot.all
        @fs.write(Hiiro::Git::Pr::PINNED_FILE, all_prs.map(&:to_pinned_h).to_yaml)
      end
      removed
    end

    def pinned?(pr_number)
      load_pinned.any? { |p| p.number.to_s == pr_number.to_s }
    end

    def fetch_pr_info(pr_number, repo: nil)
      fields = 'number,title,url,headRefName,state,statusCheckRollup,reviewDecision,reviews,isDraft,mergeable'
      repo_flag = repo ? " --repo #{repo}" : ""
      output = `gh pr view #{pr_number}#{repo_flag} --json #{fields} 2>/dev/null`.strip
      return nil if output.empty?
      Hiiro::Git::Pr.from_gh_json(JSON.parse(output))
    rescue JSON::ParserError
      nil
    end

    def fetch_current_branch_pr
      fields = 'number,title,url,headRefName,state'
      output = `gh pr view --json #{fields} 2>/dev/null`.strip
      return nil if output.empty?
      Hiiro::Git::Pr.from_gh_json(JSON.parse(output))
    rescue JSON::ParserError
      nil
    end

    def fetch_my_prs
      output = `gh pr list --author @me --state open --json number,title,headRefName,url 2>/dev/null`.strip
      return [] if output.empty?
      prs = JSON.parse(output) rescue []
      prs.map { |data| Hiiro::Git::Pr.from_gh_json(data) }
    end

    def fetch_assigned_prs
      output = `gh pr list --assignee @me --state open --json number,title,headRefName,url 2>/dev/null`.strip
      return [] if output.empty?
      prs = JSON.parse(output) rescue []
      prs.map { |data| Hiiro::Git::Pr.from_gh_json(data) }
    end

    def fetch_my_and_assigned_prs
      authored_prs = fetch_my_prs
      assigned_prs = fetch_assigned_prs

      authored_numbers = authored_prs.map(&:number).to_set
      assigned_prs.each { |pr| pr.assigned = true unless authored_numbers.include?(pr.number) }
      authored_prs.each { |pr| pr.authored = true }

      (authored_prs + assigned_prs).uniq(&:number)
    end

    def needs_refresh?(pr, force: false)
      return true if force
      return true unless pr.last_checked

      last_check_time = Time.parse(pr.last_checked) rescue nil
      return true unless last_check_time

      # Refresh if last check was more than 2 minutes ago
      (Time.now - last_check_time) > 120
    end

    def code_freeze_active?
      return @code_freeze_active unless @code_freeze_active.nil?

      output = `isc codefreeze list 2>/dev/null`.strip
      return @code_freeze_active = false if output.empty?

      now = Time.now
      @code_freeze_active = output.lines.drop(1).any? do |line|
        parts = line.strip.split(/\s{2,}/)
        next false if parts.length < 2

        start_time = Time.parse(parts[0]) rescue nil
        end_time   = Time.parse(parts[1]) rescue nil
        next false unless start_time && end_time

        now >= start_time && now <= end_time
      end
    rescue
      @code_freeze_active = false
    end

    # Overrides the ISC code freeze StatusContext in a raw statusCheckRollup array
    # to reflect the actual current freeze state rather than GitHub's cached value.
    def apply_isc_code_freeze_override!(rollup, frozen)
      return unless rollup.is_a?(Array)

      rollup.each do |ctx|
        next unless ctx['__typename'] == 'StatusContext' && ctx['context'] == 'ISC code freeze'
        ctx['state'] = frozen ? 'FAILURE' : 'SUCCESS'
      end
    end

    # Accepts an array of PR records (each with 'number' and optionally 'repo'/'url'),
    # groups them by repo, and fetches in batches per repo via GraphQL.
    def batch_fetch_pr_info(prs)
      return {} if prs.empty?

      by_repo = prs.group_by { |pr| pr_repo(pr) || 'instacart/carrot' }

      result = {}
      by_repo.each do |repo_path, repo_prs|
        owner, name = repo_path.split('/', 2)
        pr_numbers = repo_prs.map(&:number)
        result.merge!(fetch_batch_for_repo(owner, name, pr_numbers))
      end
      result
    end

    def refresh_all_status(prs, force: false, verbose: false)
      prs_to_refresh = prs.select { |pr| pr.active? && needs_refresh?(pr, force: force) }

      if prs_to_refresh.empty?
        puts "All PRs recently checked (within last 2 minutes). Use -U to force update." if verbose
        return prs
      end

      # infos is keyed by [number, repo] to avoid collisions across repos
      infos = batch_fetch_pr_info(prs_to_refresh)
      frozen = code_freeze_active?

      prs_to_refresh.each do |pr|
        info = infos[[pr.number, pr_repo(pr) || 'instacart/carrot']]
        next unless info

        rollup = info['statusCheckRollup']
        apply_isc_code_freeze_override!(rollup, frozen)

        pr.state           = info['state']
        pr.title           = info['title']
        pr.check_runs      = rollup
        pr.checks          = Hiiro::Git::Pr.summarize_checks(rollup, truncated: info['checksTruncated'])
        pr.reviews         = Hiiro::Git::Pr.summarize_reviews(info['reviews'])
        pr.review_decision = info['reviewDecision']
        pr.is_draft        = info['isDraft']
        pr.mergeable       = info['mergeable']
        pr.last_checked    = Time.now.iso8601
      end

      prs
    end

    def refresh_status(pr, force: false)
      return pr unless needs_refresh?(pr, force: force)

      info = fetch_pr_info(pr.number, repo: pr_repo(pr))
      return pr unless info

      rollup = info.check_runs
      apply_isc_code_freeze_override!(rollup, code_freeze_active?)

      pr.state           = info.state
      pr.title           = info.title
      pr.check_runs      = rollup
      pr.checks          = Hiiro::Git::Pr.summarize_checks(rollup)
      pr.reviews         = info.reviews
      pr.review_decision = info.review_decision
      pr.is_draft        = info.is_draft
      pr.mergeable       = info.mergeable
      pr.last_checked    = Time.now.iso8601
      pr
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
        if pr.checks
          c = pr.checks
          has_failed   = c['failed'].to_i > 0
          has_pending  = c['pending'].to_i > 0
          only_frozen  = has_failed && c['failed'].to_i == c['frozen'].to_i
          emoji = if has_failed && has_pending
            only_frozen ? "⏳❄️" : "⏳❌"
          elsif has_failed
            only_frozen ? "　❄️" : "　❌"
          elsif has_pending
            "⏳　"
          elsif c['truncated']
            "　❓"
          else
            "　✅"
          end
          succ  = c['success'].to_i.to_s.rjust(succ_w)
          total = c['total'].to_i.to_s.rjust(total_w)
          [emoji, "#{succ}/#{total}"]
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

      repo = pr_repo(pr)
      repo_label = (repo && repo != 'instacart/carrot') ? "[#{repo}] " : ""

      tags = Array(pr.tags)
      tags_str = tags.any? ? tags.map { |t| "\e[30;104m#{t}\e[0m" }.join(' ') : nil

      branch_str = pr.head_branch ? " \e[90m#{pr.head_branch}\e[0m" : ""
      title_str = "\e[1m#{pr.title}\e[0m"
      line1 = "#{num} ##{pr.number} #{state_icon} #{reviews_str}#{branch_str}"
      line2 = "#{indent}#{repo_label}#{title_str}"
      line3 = pr.url ? "#{indent}#{pr.url}" : nil
      line4 = tags_str ? "#{indent}#{tags_str}" : nil

      if oneline
        "#{line1} #{repo_label}#{title_str}#{tags_str ? "  #{tags_str}" : ""}"
      else
        [line1, line2, line3, line4].compact.join("\n")
      end
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

      repo = pr_repo(pr)
      repo_label = (repo && repo != 'instacart/carrot') ? " [#{repo}]" : ""

      lines << "#{num} ##{pr.number}#{repo_label} - #{pr.title}"
      lines << "   State: #{state_str}"
      lines << "   Branch: #{pr.head_branch}" if pr.head_branch
      lines << "   URL: #{pr.url}" if pr.url

      if pr.checks
        c = pr.checks
        check_status = if c['failed'] > 0
          "FAILING (#{c['success']}/#{c['total']} passed, #{c['failed']} failed)"
        elsif c['pending'] > 0
          "PENDING (#{c['success']}/#{c['total']} passed, #{c['pending']} pending)"
        else
          "PASSING (#{c['success']}/#{c['total']})"
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

    def pr_yaml_lines(prs = nil)
      (prs || load_pinned).map do |pr|
        branch = pr.head_branch ? "[#{pr.head_branch}]" : "[##{pr.number}]"
        "- #{pr.number}  # #{branch} #{pr.title}"
      end
    end

    def strip_ansi(str)
      str.gsub(/\e\[[0-9;]*m/, '')
    end

    def display_check_runs(pr, indent: "   ")
      runs = pr.check_runs
      return unless runs.is_a?(Array) && runs.any?

      runs.each do |run|
        case run['__typename']
        when 'CheckRun'
          emoji = check_run_emoji(run['conclusion'], run['status'])
          name  = run['name'] || run['workflowName'] || '(unknown)'
          url   = run['detailsUrl']
        when 'StatusContext'
          emoji = status_context_emoji(run['state'])
          name  = run['context'] || '(unknown)'
          url   = run['targetUrl']
        else
          emoji = '?'
          name  = run['name'] || run['context'] || '(unknown)'
          url   = run['detailsUrl'] || run['targetUrl']
        end

        line = "#{indent}#{emoji}  #{name}"
        line += "\n#{indent}   #{url}" if url
        puts line
      end
    end

    private

    def fetch_batch_for_repo(owner, name, pr_numbers)
      return {} if pr_numbers.empty?

      context_fragment = <<~GRAPHQL.strip
        __typename
        ... on CheckRun { __typename name conclusion status detailsUrl }
        ... on StatusContext { __typename context state targetUrl }
      GRAPHQL

      pr_queries = pr_numbers.map.with_index do |num, idx|
        <<~GRAPHQL.strip
          pr#{idx}: pullRequest(number: #{num}) {
            number title url headRefName state isDraft mergeable reviewDecision
            statusCheckRollup {
              contexts(last: 100) {
                totalCount
                pageInfo { hasPreviousPage startCursor }
                nodes { #{context_fragment} }
              }
            }
            reviews(last: 50) { nodes { author { login } state } }
          }
        GRAPHQL
      end

      query = <<~GRAPHQL
        query {
          repository(owner: "#{owner}", name: "#{name}") {
            #{pr_queries.join("\n")}
          }
        }
      GRAPHQL

      result = `gh api graphql -f query='#{query.gsub("'", "'\\''")}' 2>/dev/null`
      return {} if result.empty?

      data = JSON.parse(result)
      repo_data = data.dig('data', 'repository')
      return {} unless repo_data

      pr_info_by_key = {}
      repo_path = "#{owner}/#{name}"
      pr_numbers.each_with_index do |num, idx|
        pr_data = repo_data["pr#{idx}"]
        next unless pr_data

        contexts_data = pr_data.dig('statusCheckRollup', 'contexts')
        nodes       = contexts_data&.[]('nodes') || []
        total_count = contexts_data&.[]('totalCount').to_i
        page_info   = contexts_data&.[]('pageInfo') || {}

        # Paginate backwards to collect all checks beyond the first 100
        all_nodes = nodes.dup
        cursor = page_info['startCursor']
        while page_info['hasPreviousPage'] && cursor
          extra_nodes, page_info = fetch_contexts_page(owner, name, num, cursor, context_fragment)
          break unless extra_nodes
          all_nodes = extra_nodes + all_nodes
          cursor = page_info&.[]('startCursor')
        end

        truncated = total_count > 0 && all_nodes.length < total_count

        pr_info_by_key[[num, repo_path]] = {
          'number'           => pr_data['number'],
          'title'            => pr_data['title'],
          'url'              => pr_data['url'],
          'headRefName'      => pr_data['headRefName'],
          'state'            => pr_data['state'],
          'isDraft'          => pr_data['isDraft'],
          'mergeable'        => pr_data['mergeable'],
          'reviewDecision'   => pr_data['reviewDecision'],
          'statusCheckRollup'=> all_nodes.any? ? all_nodes : nil,
          'checksTruncated'  => truncated,
          'reviews'          => pr_data.dig('reviews', 'nodes') || [],
          'repo'             => repo_path
        }
      end

      pr_info_by_key
    rescue JSON::ParserError, StandardError
      {}
    end

    def fetch_contexts_page(owner, name, pr_number, before_cursor, context_fragment)
      query = <<~GRAPHQL
        query {
          repository(owner: "#{owner}", name: "#{name}") {
            pullRequest(number: #{pr_number}) {
              statusCheckRollup {
                contexts(last: 100, before: "#{before_cursor}") {
                  pageInfo { hasPreviousPage startCursor }
                  nodes { #{context_fragment} }
                }
              }
            }
          }
        }
      GRAPHQL

      result = `gh api graphql -f query='#{query.gsub("'", "'\\''")}' 2>/dev/null`
      return [nil, nil] if result.empty?

      contexts = JSON.parse(result).dig('data', 'repository', 'pullRequest', 'statusCheckRollup', 'contexts')
      return [nil, nil] unless contexts

      [contexts['nodes'] || [], contexts['pageInfo'] || {}]
    rescue JSON::ParserError, StandardError
      [nil, nil]
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
