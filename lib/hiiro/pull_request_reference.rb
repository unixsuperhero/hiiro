class Hiiro
  # host/owner/name of a GitHub repository.
  class RepositoryIdentity
    def self.parse(input)
      text = input.to_s.strip
      if (m = text.match(%r{github\.com[/:]([^/\s]+)/([^/\s#?]+)}))
        new(host: 'github.com', owner: m[1], name: m[2].delete_suffix('.git'))
      elsif (m = text.match(%r{\A([^/\s#]+)/([^/\s#]+)\z}))
        new(host: 'github.com', owner: m[1], name: m[2])
      end
    end

    attr_reader :host, :owner, :name

    def initialize(host: 'github.com', owner:, name:)
      @host = host
      @owner = owner
      @name = name
    end

    def path = "#{owner}/#{name}"
    def url  = "https://#{host}/#{path}"
    def to_s = path

    def ==(other)
      other.is_a?(RepositoryIdentity) && [host, owner, name] == [other.host, other.owner, other.name]
    end
    alias eql? ==

    def hash = [host, owner, name].hash
  end

  # A PR number and the repository it belongs to. A bare number has no
  # repository until explicit context (a tracked record, a URL, gh's current
  # repository) qualifies it; persistence accepts qualified references only.
  class PullRequestReference
    URL_PATTERN = %r{github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)}
    QUALIFIED_PATTERN = %r{\A([^/\s#]+/[^/\s#]+)#(\d+)\z}

    def self.from_url(url)
      m = url.to_s.match(URL_PATTERN) or return nil
      new(number: m[3], repo: RepositoryIdentity.new(owner: m[1], name: m[2]))
    end

    # URL | 'owner/name#123' | '#123' | '123' | 123 → reference, or nil when none of those.
    # repo: qualifies a bare number; it never overrides a URL or owner/name#N.
    def self.parse(input, repo: nil)
      text = input.to_s.strip
      return from_url(text) if text.match?(URL_PATTERN)
      if (m = text.match(QUALIFIED_PATTERN))
        return new(number: m[2], repo: RepositoryIdentity.parse(m[1]))
      end

      m = text.match(/\A#?(\d+)\z/) or return nil
      repo = RepositoryIdentity.parse(repo) unless repo.nil? || repo.is_a?(RepositoryIdentity)
      new(number: m[1], repo: repo)
    end

    # A qualified reference or nil: bare numbers are rejected.
    def self.qualified(input)
      ref = parse(input)
      ref if ref&.qualified?
    end

    attr_reader :repo, :number

    def initialize(number:, repo: nil)
      @number = number.to_i
      @repo = repo
    end

    def qualified?    = !repo.nil? && number.positive?
    def number_string = number.to_s
    def url           = repo && "#{repo.url}/pull/#{number}"
    def key           = [number, repo&.path]
    def repo_args     = repo ? ['-R', repo.path] : []
    def to_s          = repo ? "#{repo.path}##{number}" : "##{number}"

    def ==(other) = other.is_a?(PullRequestReference) && number == other.number && repo == other.repo
    alias eql? ==
    def hash = [number, repo].hash
  end
end
