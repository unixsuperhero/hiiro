# A controlled `gh` for tests and smokes; it never reaches GitHub.
# Install with FakeGh.install(dir, state_path) and put dir first on PATH.
#
# State (JSON, re-read on every call so a test can change it between runs):
#   { "prs": { "team/one#42": { "title": "...", "state": "OPEN", "head": "aaa...",
#                               "checks": 150 | [nodes], "reviews": 60 | [nodes],
#                               "fail":   { "checks": { "2": "exit" | "malformed" | "errors" } },
#                               "head_at": { "reviews": { "2": "bbb..." } },
#                               "repeat_cursor": { "checks": true },
#                               "error": { "reviews": "message" } } },
#     "current": "https://github.com/team/one/pull/42",   # gh pr view with no argument
#     "repo": "team/one",                                   # gh's current repository
#     "mine": ["https://github.com/team/one/pull/42"],
#     "hooks": { "team/one#42:checks:2": ["/abs/ruby", "..."] } }   # run before answering
# Every call is appended to $FAKE_GH_LOG as one JSON argv line.
require 'json'

module FakeGh
  PAGE = 100

  def self.install(dir, state_path, log_path)
    path = File.join(dir, 'gh')
    File.write(path, <<~SH)
      #!/bin/sh
      FAKE_GH_STATE=#{state_path.inspect} FAKE_GH_LOG=#{log_path.inspect} exec #{RbConfig.ruby.inspect} #{File.expand_path(__FILE__).inspect} "$@"
    SH
    File.chmod(0o755, path)
    path
  end

  def self.main(argv)
    File.open(ENV.fetch('FAKE_GH_LOG'), 'a') { |f| f.puts(JSON.generate(argv)) }
    @state = JSON.parse(File.read(ENV.fetch('FAKE_GH_STATE')))
    case argv.first(2)
    when %w[api graphql] then graphql(argv.drop(2))
    when %w[pr view]     then pr_view(argv.drop(2))
    when %w[pr list]     then pr_list
    else fail_with("fake gh: unsupported #{argv.join(' ')}")
    end
  end

  def self.fail_with(message, code = 1)
    warn message
    exit code
  end

  def self.hook(key)
    argv = (@state['hooks'] || {})[key]
    system(*argv, out: :err, exception: true) if argv
  end

  def self.pr(key) = (@state['prs'] || {})[key]

  def self.nodes(pr, kind)
    value = pr[kind]
    return value if value.is_a?(Array)

    Array.new(value.to_i) do |i|
      if kind == 'checks'
        { '__typename' => 'CheckRun', 'name' => "check-#{i + 1}", 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS',
          'detailsUrl' => "https://ci.example.test/#{i + 1}" }
      else
        { 'author' => { 'login' => "reviewer-#{i + 1}" }, 'state' => 'APPROVED', 'submittedAt' => '2026-10-01T00:00:00Z' }
      end
    end
  end

  # Nodes [start, finish) in GitHub's backward paging, cursors "kind:start".
  def self.connection(pr, kind, before: nil)
    all = nodes(pr, kind)
    finish = before ? before.split(':').last.to_i : all.length
    start = [finish - PAGE, 0].max
    cursor = (pr['repeat_cursor'] || {})[kind] && before ? before : "#{kind}:#{start}"
    { 'totalCount' => all.length, 'pageInfo' => { 'hasPreviousPage' => start.positive?, 'startCursor' => cursor },
      'nodes' => all[start...finish] }
  end

  def self.page_number(pr, kind, before) = 1 + (nodes(pr, kind).length - before.split(':').last.to_i) / PAGE

  def self.head(pr, kind, page)
    changes = (pr['head_at'] || {})[kind] || {}
    changed = changes.select { |from, _| page >= from.to_i }.max_by { |from, _| from.to_i }
    changed ? changed.last : pr.fetch('head')
  end

  def self.graphql(args)
    vars = {}
    args.each_slice(2) { |flag, pair| key, value = pair.split('=', 2); vars[key] = flag == '-F' ? value.to_i : value }
    query = vars.fetch('query')
    repo = "#{vars.fetch('owner')}/#{vars.fetch('name')}"
    vars.key?('before') ? page(query, repo, vars) : batch(query, repo)
  end

  def self.batch(query, repo)
    hook("batch:#{repo}")
    data = {}
    errors = []
    query.scan(/(pr\d+): pullRequest\(number: (\d+)\)/).each do |name, number|
      pr = pr("#{repo}##{number}")
      unless pr
        data[name] = nil
        errors << { 'path' => ['repository', name], 'message' => "Could not resolve to a PullRequest with the number of #{number}." }
        next
      end
      node = pr.slice('title', 'state', 'isDraft', 'mergeable', 'reviewDecision').merge(
        'number' => number.to_i, 'url' => "https://github.com/#{repo}/pull/#{number}",
        'headRefName' => pr['headRefName'] || "branch-#{number}", 'headRefOid' => head(pr, 'checks', 1),
        'statusCheckRollup' => { 'contexts' => connection(pr, 'checks') }, 'reviews' => connection(pr, 'reviews'))
      (pr['error'] || {}).each do |kind, message|
        field = kind == 'checks' ? 'statusCheckRollup' : 'reviews'
        node[field] = nil
        errors << { 'path' => ['repository', name, field], 'message' => message }
      end
      data[name] = node
    end
    respond({ 'data' => { 'repository' => data } }.merge(errors.empty? ? {} : { 'errors' => errors }))
  end

  def self.page(query, repo, vars)
    kind = query.include?('statusCheckRollup') ? 'checks' : 'reviews'
    key = "#{repo}##{vars.fetch('number')}"
    pr = pr(key) or return respond('data' => { 'repository' => { 'pullRequest' => nil } })
    number = page_number(pr, kind, vars.fetch('before'))
    hook("#{key}:#{kind}:#{number}")
    case ((pr['fail'] || {})[kind] || {})[number.to_s]
    when 'exit'      then fail_with('HTTP 502: Bad Gateway (https://api.github.com/graphql)')
    when 'malformed' then return puts('<html>bad gateway</html>')
    when 'errors'    then return respond('data' => nil, 'errors' => [{ 'message' => 'Something went wrong while executing your query.' }])
    end
    conn = connection(pr, kind, before: vars.fetch('before'))
    inner = kind == 'checks' ? { 'statusCheckRollup' => { 'contexts' => conn } } : { 'reviews' => conn }
    respond('data' => { 'repository' => { 'pullRequest' => { 'headRefOid' => head(pr, kind, number) }.merge(inner) } })
  end

  def self.respond(body)
    puts JSON.generate(body)
    exit(body['errors'] ? 1 : 0)
  end

  def self.pr_view(args)
    target = args.first&.start_with?('-') ? nil : args.first
    url = if target.nil? then @state['current']
          elsif target.match?(%r{/pull/\d+}) then target
          else "https://github.com/#{@state.fetch('repo')}/pull/#{target}"
          end
    key = url && url.match(%r{github\.com/([^/]+/[^/]+)/pull/(\d+)})&.captures&.join('#')
    pr = key && pr(key) or fail_with('no pull requests found')
    puts JSON.generate(view(key, pr))
  end

  def self.view(key, pr)
    repo, number = key.split('#')
    { 'number' => number.to_i, 'url' => "https://github.com/#{repo}/pull/#{number}", 'title' => pr['title'],
      'headRefName' => pr['headRefName'] || "branch-#{number}", 'state' => pr['state'] }
  end

  def self.pr_list
    keys = Array(@state['mine']).map { |url| url.match(%r{github\.com/([^/]+/[^/]+)/pull/(\d+)}).captures.join('#') }
    puts JSON.generate(keys.map { |key| view(key, pr(key)) })
  end
end

FakeGh.main(ARGV) if $PROGRAM_NAME == __FILE__
