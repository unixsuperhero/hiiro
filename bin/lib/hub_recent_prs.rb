require 'json'
require 'open3'
require 'time'

# Live "recent PRs" for `h hub recent prs` / `h hub latest prs`: the pull
# requests the signed-in GitHub user authored, newest update first, read from
# `gh search prs` (any state). Nothing is cached or written.
module HubRecentPRs
  MAX_LIMIT = 1000 # GitHub search returns at most 1000 results
  FIELDS    = 'number,title,url,updatedAt,repository,state'.freeze
  REPO_PATTERN = %r{\A[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.][A-Za-z0-9_.-]*\z}

  module_function

  # => [{ 'name' => 'owner/repo#12 Title', 'path' => PR URL,
  #       'timestamp' => '2026-10-04T17:59:05Z', 'basis' => 'updated' }], newest first
  def fetch(limit:, repo: nil)
    limit = validate_limit(limit)
    raise Hub::Error, "invalid --repo #{repo.inspect} (expected OWNER/REPO)" if repo && repo !~ REPO_PATTERN

    argv = ['gh', 'search', 'prs', '--author', '@me', '--sort', 'updated', '--order', 'desc',
            '--limit', limit.to_s, '--json', FIELDS]
    argv += ['--repo', repo] if repo
    normalize(run(argv), limit)
  end

  def validate_limit(limit)
    n = Integer(limit, exception: false)
    raise Hub::Error, "invalid limit #{limit.inspect} (expected a positive integer)" unless n && n.positive?
    raise Hub::Error, "limit #{n} exceeds the GitHub search maximum of #{MAX_LIMIT} for prs" if n > MAX_LIMIT

    n
  end

  def run(argv)
    out, err, status = Open3.capture3({ 'GH_PROMPT_DISABLED' => '1' }, *argv)
    return out if status.success?

    detail = err.to_s.strip.lines.first.to_s.strip
    detail = "exit #{status.exitstatus}" if detail.empty?
    raise Hub::Error, "gh search prs failed: #{detail}"
  rescue Errno::ENOENT
    raise Hub::Error, 'gh is not installed or not on PATH (needed for prs)'
  rescue SystemCallError => e
    raise Hub::Error, "cannot run gh: #{e.message}"
  end

  def normalize(json, limit)
    data = begin
      JSON.parse(json)
    rescue JSON::ParserError => e
      raise Hub::Error, "gh returned malformed JSON: #{e.message[0, 80]}"
    end
    raise Hub::Error, 'gh returned unexpected JSON (expected an array)' unless data.is_a?(Array)

    data.map { |pr| record(pr) }
        .sort_by { |r| [-Time.iso8601(r['timestamp']).to_r, r['path']] }
        .first(limit)
  end

  def record(pr)
    raise Hub::Error, 'gh returned a non-object result' unless pr.is_a?(Hash)

    number = pr['number']
    repo   = pr.dig('repository', 'nameWithOwner') if pr['repository'].is_a?(Hash)
    title  = pr['title']
    url    = pr['url']
    at     = pr['updatedAt']
    raise Hub::Error, 'gh result is missing a valid number' unless number.is_a?(Integer)
    raise Hub::Error, 'gh result is missing repository.nameWithOwner' unless repo.is_a?(String) && !repo.empty?
    raise Hub::Error, 'gh result is missing title' unless title.is_a?(String)
    raise Hub::Error, 'gh result is missing url' unless url.is_a?(String) && !url.empty?
    raise Hub::Error, 'gh result is missing updatedAt' unless at.is_a?(String)

    stamp = begin
      Time.iso8601(at).utc
    rescue ArgumentError
      raise Hub::Error, "gh result has an invalid updatedAt #{at.inspect}"
    end

    { 'name' => "#{repo}##{number} #{title.gsub(/\s+/, ' ').strip}".strip,
      'path' => url,
      'timestamp' => stamp.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'basis' => 'updated' }
  end
end
