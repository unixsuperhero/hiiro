require 'json'
require 'set'
require 'time'

class Hiiro
  # What GitHub reported for one qualified PR at one head revision. Remote
  # evidence only: tags, task, monitoring, and dependencies live on the
  # tracked record and are never part of a snapshot.
  #
  #   { reference: team/one#42, head_sha: 'abc123', fetched_at: '2026-10-13T10:00:00.000000Z',
  #     fields: { 'title' => ..., 'state' => 'OPEN', ... },
  #     checks:  Part(nodes: [raw rollup nodes], complete: true,  error: nil),
  #     reviews: Part(nodes: [raw review nodes], complete: false, error: 'reviews page 2: ...') }
  class PrSnapshot
    # complete: every node GitHub reported for this head was fetched. A
    # complete part with no nodes is known-empty, not unknown.
    Part = Struct.new(:nodes, :complete, :error, keyword_init: true) do
      def known_empty? = complete && nodes.empty?
    end

    # A refresh that produced no usable observation for the reference.
    Failure = Struct.new(:reference, :error, keyword_init: true)

    FIELDS = {
      'title' => :title, 'state' => :state, 'url' => :url, 'headRefName' => :head_ref_name,
      'isDraft' => :is_draft, 'mergeable' => :mergeable, 'reviewDecision' => :review_decision,
    }.freeze

    attr_reader :reference, :head_sha, :fetched_at, :fields, :checks, :reviews

    def initialize(reference:, head_sha:, fetched_at:, fields:, checks:, reviews:)
      @reference = reference
      @head_sha = head_sha
      @fetched_at = fetched_at
      @fields = fields
      @checks = checks
      @reviews = reviews
    end

    def complete? = checks.complete && reviews.complete
    def error     = [checks.error, reviews.error].compact.join('; ').then { |text| text.empty? ? nil : text }

    # Repository-batched GraphQL fetch through `gh api graphql` (argv, real
    # exit status). Checks and reviews page backward 100 nodes at a time;
    # every page re-reads headRefOid so pages from two heads never combine.
    class Fetcher
      PAGE = 100
      CONTEXT = <<~GRAPHQL.strip
        __typename
        ... on CheckRun { name conclusion status detailsUrl }
        ... on StatusContext { context state targetUrl }
      GRAPHQL
      REVIEW = 'author { login } state submittedAt'
      HeadChanged = Class.new(StandardError)

      def initialize(runner: ->(*argv) { Hiiro::Shell.run3(*argv) }, clock: -> { Time.now.utc })
        @runner = runner
        @clock = clock
      end

      # [reference] → { reference => PrSnapshot | Failure }. Every reference must be qualified.
      def fetch(references)
        references.uniq.group_by(&:repo).each_with_object({}) do |(repo, refs), out|
          out.merge!(fetch_repository(repo, refs))
        end
      end

      private

      def fetch_repository(repo, refs)
        aliases = refs.each_with_index.map { |ref, i| "pr#{i}: pullRequest(number: #{ref.number}) { #{pr_fields} }" }
        query = "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { #{aliases.join(' ')} } }"
        response = request(query, owner: repo.owner, name: repo.name)
        refs.each_with_index.to_h do |ref, i|
          [ref, observe(repo, ref, response, "pr#{i}")]
        end
      end

      def observe(repo, ref, response, key)
        return Failure.new(reference: ref, error: response.failure) if response.failure
        errors = response.errors_for('repository', key)
        data = response.data&.dig('repository', key)
        return Failure.new(reference: ref, error: errors.first || response.general_error || 'not returned by GitHub') unless data

        head = data['headRefOid']
        return Failure.new(reference: ref, error: 'GitHub returned no head revision') unless head

        checks_error = errors.find { |message| message.include?('statusCheckRollup') }
        reviews_error = errors.find { |message| message.include?('reviews') }
        other_error = (errors - [checks_error, reviews_error]).first
        checks = collect(:checks, repo, ref, head, data.dig('statusCheckRollup', 'contexts'),
                         checks_error || other_error, rollup_present: !data['statusCheckRollup'].nil?)
        reviews = collect(:reviews, repo, ref, head, data['reviews'], reviews_error || other_error)
        PrSnapshot.new(reference: ref, head_sha: head, fetched_at: @clock.call.iso8601(6),
                       fields: FIELDS.keys.to_h { |field| [field, data[field]] }, checks: checks, reviews: reviews)
      rescue HeadChanged => error
        Failure.new(reference: ref, error: error.message)
      end

      def collect(kind, repo, ref, head, connection, error, rollup_present: true)
        return Part.new(nodes: [], complete: false, error: "#{kind}: #{error}") if error
        return Part.new(nodes: [], complete: true, error: nil) if kind == :checks && !rollup_present
        return Part.new(nodes: [], complete: false, error: "#{kind}: not returned by GitHub") unless connection.is_a?(Hash)

        nodes = Array(connection['nodes'])
        total = connection['totalCount']
        info = connection['pageInfo'] || {}
        seen = Set.new
        page = 1
        while info['hasPreviousPage']
          cursor = info['startCursor']
          return Part.new(nodes: nodes, complete: false, error: "#{kind}: page #{page + 1} has no cursor") unless cursor
          return Part.new(nodes: nodes, complete: false, error: "#{kind}: repeated cursor #{cursor}") unless seen.add?(cursor)

          page += 1
          response = request(page_query(kind), owner: repo.owner, name: repo.name, number: ref.number, before: cursor)
          pr = response.data&.dig('repository', 'pullRequest')
          problem = response.failure || response.errors_for.first || response.general_error || ('no data' unless pr)
          if pr && pr['headRefOid'] && pr['headRefOid'] != head
            raise HeadChanged, "head changed during refresh (#{head[0, 7]} → #{pr['headRefOid'][0, 7]} at #{kind} page #{page})"
          end
          return Part.new(nodes: nodes, complete: false, error: "#{kind}: page #{page} failed: #{problem}") if problem

          connection = kind == :checks ? pr.dig('statusCheckRollup', 'contexts') : pr['reviews']
          return Part.new(nodes: nodes, complete: false, error: "#{kind}: page #{page} failed: no nodes") unless connection.is_a?(Hash)

          nodes = Array(connection['nodes']) + nodes
          info = connection['pageInfo'] || {}
        end
        return Part.new(nodes: nodes, complete: true, error: nil) if total.nil? || nodes.length == total

        Part.new(nodes: nodes, complete: false, error: "#{kind}: #{nodes.length} of #{total} fetched")
      end

      def pr_fields
        <<~GRAPHQL.split.join(' ')
          number title url headRefName headRefOid state isDraft mergeable reviewDecision
          statusCheckRollup { contexts(last: #{PAGE}) { #{connection_fields(CONTEXT)} } }
          reviews(last: #{PAGE}) { #{connection_fields(REVIEW)} }
        GRAPHQL
      end

      def connection_fields(node) = "totalCount pageInfo { hasPreviousPage startCursor } nodes { #{node} }"

      def page_query(kind)
        inner = if kind == :checks
          "statusCheckRollup { contexts(last: #{PAGE}, before: $before) { #{connection_fields(CONTEXT)} } }"
        else
          "reviews(last: #{PAGE}, before: $before) { #{connection_fields(REVIEW)} }"
        end
        "query($owner: String!, $name: String!, $number: Int!, $before: String!) { " \
          "repository(owner: $owner, name: $name) { pullRequest(number: $number) { headRefOid #{inner} } } }".split.join(' ')
      end

      Response = Struct.new(:data, :errors, :failure, :status_error, keyword_init: true) do
        # GraphQL error messages whose path starts with the given segments.
        def errors_for(*prefix)
          errors.select { |error| prefix.empty? || Array(error['path']).first(prefix.length) == prefix }
                .map { |error| "#{Array(error['path']).join('.')}: #{error['message']}".delete_prefix(': ') }
        end

        def general_error
          messages = errors.reject { |error| error['path'] }.map { |error| error['message'] }
          messages.first || status_error
        end
      end

      def request(query, **variables)
        argv = ['gh', 'api', 'graphql', '-f', "query=#{query}"]
        variables.each { |key, value| argv.push(value.is_a?(Integer) ? '-F' : '-f', "#{key}=#{value}") }
        result = @runner.call(*argv)
        status = result.success? ? nil : "gh exited #{result.exit_code}: #{result.stderr.to_s.strip}"
        body = begin
          JSON.parse(result.stdout.to_s)
        rescue JSON::ParserError
          nil
        end
        return Response.new(errors: [], failure: status || 'malformed gh output') unless body.is_a?(Hash) && (body.key?('data') || body.key?('errors'))

        errors = Array(body['errors']).select { |error| error.is_a?(Hash) }
        failure = body['data'].nil? ? (errors.first&.dig('message') || status || 'no data') : nil
        Response.new(data: body['data'], errors: errors, failure: failure, status_error: status)
      rescue SystemCallError => error
        Response.new(errors: [], failure: "gh could not start: #{error.message}")
      end
    end
  end
end
