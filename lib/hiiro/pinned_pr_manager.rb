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

    def pr_repo(pr)
      pr.repo || Hiiro::Git::Pr.repo_from_url(pr.url)
    end

    def load_pinned = Hiiro::PinnedPr.by_slot.all

    def reference_text(pr) = pr.reference.url || pr.number.to_s

    def find(ref, pinned_only: true)
      if ref.is_a?(Hiiro::PinnedPr)
        scope = Hiiro::PinnedPr.where(id: ref.id)
        scope = scope.where(pinned: true) if pinned_only
        return scope.first
      end
      reference = if ref.respond_to?(:number) && ref.respond_to?(:repo)
        Hiiro::PullRequestReference.new(number: ref.number, repo: Hiiro::RepositoryIdentity.parse(ref.repo || ref.url))
      elsif ref.is_a?(Hiiro::PullRequestReference)
        ref
      elsif (match = ref.to_s.match(/\A([^\s#]+\/[^\s#]+)#(\d+)\z/))
        Hiiro::PullRequestReference.new(number: match[2], repo: Hiiro::RepositoryIdentity.parse(match[1]))
      else
        Hiiro::PullRequestReference.parse(ref)
      end
      reference && Hiiro::PinnedPr.find_by_reference(reference, pinned_only: pinned_only)
    end

    def pin(pr)
      Hiiro::DB.connection.transaction(mode: :immediate) do
        existing = find(pr, pinned_only: false)
        raise Hiiro::Error, 'PR was removed while pinning' if pr.is_a?(Hiiro::PinnedPr) && !existing
        if existing
          attrs = Hiiro::PinnedPr.from_git_pr(pr).values
          %i[title state url head_ref_name is_draft mergeable review_decision checks_json check_runs_json reviews_json last_checked].each do |field|
            existing[field] = attrs[field] unless attrs[field].nil?
          end
          unless existing.pinned
            existing.pinned = true
            existing.slot ||= Hiiro::PinnedPr.max(:slot).to_i + 1
            existing.pinned_at ||= Time.now.iso8601
          end
          existing.save_changes
        else
          existing = Hiiro::PinnedPr.from_git_pr(pr)
          existing.repo ||= Hiiro::Git::Pr.repo_from_url(pr.url)
          existing.slot = Hiiro::PinnedPr.max(:slot).to_i + 1
          existing.pinned_at ||= Time.now.iso8601
          existing.save
        end
        existing.sync_check_runs
        existing
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

    def change_dependencies(ref, add: [], remove: [], clear: false)
      mutate_array(ref, :depends_on, add: add, remove: remove, clear: clear)
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

    def edit_rows(prs)
      prs.map { |pr| { 'id' => pr.id }.merge(EDIT_FIELDS.to_h { |field| [field, pr.public_send(field)] }) }
    end

    def edit_baseline(prs)
      prs.to_h do |pr|
        [pr.id, { record: pr,
                  tags: Hiiro::Tag.where(taggable_type: 'PinnedPr', taggable_id: pr.id.to_s).order(:id).all.map(&:values),
                  checks: Hiiro::CheckRun.where(pr_id: pr.id).order(:id).all.map(&:values) }]
      end
    end

    def apply_edits(rows, baseline:)
      raise Hiiro::Error, 'Expected a list of PR records' unless rows.is_a?(Array)
      originals = baseline.transform_values { |entry| entry.fetch(:record) }
      ids = rows.map do |row|
        raise Hiiro::Error, 'Each PR needs its original integer id' unless row.is_a?(Hash) && row['id'].is_a?(Integer) && originals.key?(row['id'])
        raise Hiiro::Error, 'Unknown PR edit field' unless (row.keys - ['id'] - EDIT_FIELDS).empty?
        %w[tags depends_on].each do |field|
          value = row[field]
          valid = value.nil? || (value.is_a?(Array) && value.all? { |v| field == 'tags' ? v.is_a?(String) : v.is_a?(Integer) && v.positive? })
          raise Hiiro::Error, "Invalid #{field}" unless valid
        end
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
        (originals.keys - ids).each do |id|
          before = originals.fetch(id)
          current = find(before)
          next unless current
          relations = edit_baseline([current]).fetch(id)
          unchanged = current.values == before.values && %i[tags checks].all? { |key| relations[key] == baseline.fetch(id)[key] }
          raise Hiiro::Error, "Conflict deleting PR id #{id}" unless unchanged
          unpin(current)
        end
      end
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

        changes = { last_checked: Time.now.iso8601 }
        { 'state' => :state, 'title' => :title, 'reviewDecision' => :review_decision, 'isDraft' => :is_draft, 'mergeable' => :mergeable }.each do |key, field|
          changes[field] = info[key] if info.key?(key)
        end
        if info.key?('statusCheckRollup')
          changes[:check_runs] = rollup
          changes[:checks] = Hiiro::Git::Pr.summarize_checks(rollup, truncated: info['checksTruncated'])
        end
        changes[:reviews] = Hiiro::Git::Pr.summarize_reviews(info['reviews']) if info.key?('reviews')
        persist_status(pr, changes)
      end

      prs
    end

    def refresh_status(pr, force: false)
      return pr unless needs_refresh?(pr, force: force)

      info = fetch_pr_info(pr.number, repo: pr_repo(pr))
      return pr unless info

      rollup = info.check_runs
      apply_isc_code_freeze_override!(rollup, code_freeze_active?)

      persist_status(pr, state: info.state, title: info.title, check_runs: rollup,
                     checks: Hiiro::Git::Pr.summarize_checks(rollup), reviews: info.reviews,
                     review_decision: info.review_decision, is_draft: info.is_draft,
                     mergeable: info.mergeable, last_checked: Time.now.iso8601)
      pr
    end

    def persist_status(pr, changes)
      Hiiro::DB.connection.transaction(mode: :immediate) do
        current = pr.is_a?(Hiiro::PinnedPr) ? find(pr) : nil
        return nil if pr.is_a?(Hiiro::PinnedPr) && !current
        changes.each { |field, value| (current || pr).public_send("#{field}=", value) }
        if current
          current.save_changes
          current.sync_check_runs if changes.key?(:check_runs)
          changes.each { |field, value| pr.public_send("#{field}=", value) }
        end
        current || pr
      end
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

    def pr_yaml_lines(prs = nil)
      (prs || load_pinned).map do |pr|
        branch = pr.head_branch ? "[#{pr.head_branch}]" : "[##{pr.number}]"
        "- #{reference_text(pr)}  # #{branch} #{pr.title}"
      end
    end

    def strip_ansi(str)
      str.gsub(/\e\[[0-9;]*m/, '')
    end

    def display_check_runs(pr, indent: "   ")
      contexts = pr.check_summary&.contexts
      return unless contexts&.any?

      contexts.each do |ctx|
        emoji = case ctx.kind
                when :check_run      then check_run_emoji(ctx.raw['conclusion'], ctx.raw['status'])
                when :status_context then status_context_emoji(ctx.raw['state'])
                else '?'
                end
        line = "#{indent}#{emoji}  #{ctx.name}"
        line += "\n#{indent}   #{ctx.url}" if ctx.url
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
