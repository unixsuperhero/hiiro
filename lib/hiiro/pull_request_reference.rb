class Hiiro
  # host/owner/name of a GitHub repository.
  class RepositoryIdentity
    def self.parse(input)
      text = input.to_s.strip
      if (m = text.match(%r{github\.com[/:]([^/\s]+)/([^/\s#?]+)}))
        new(host: 'github.com', owner: m[1], name: m[2].delete_suffix('.git'))
      elsif (m = text.match(%r{\A([^/\s]+)/([^/\s]+)\z}))
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

  # A PR number, with the repository it belongs to when that is known.
  class PullRequestReference
    URL_PATTERN = %r{github\.com/([^/]+)/([^/]+)/pull/(\d+)}

    def self.from_url(url)
      m = url.to_s.match(URL_PATTERN) or return nil
      new(number: m[3], repo: RepositoryIdentity.new(owner: m[1], name: m[2]))
    end

    # URL | '#123' | '123' | 123 → reference, or nil when none of those.
    def self.parse(input, default_repo: nil)
      return from_url(input) if input.to_s.match?(URL_PATTERN)

      m = input.to_s.strip.match(/\A#?(\d+)\z/) or return nil
      repo = default_repo.is_a?(RepositoryIdentity) ? default_repo : RepositoryIdentity.parse(default_repo)
      new(number: m[1], repo: repo)
    end

    attr_reader :repo, :number

    def initialize(number:, repo: nil)
      @number = number.to_i
      @repo = repo
    end

    def number_string = number.to_s
    def url           = repo && "#{repo.url}/pull/#{number}"
    def key           = [number, repo&.path]
    def repo_args     = repo ? ['-R', repo.path] : []
    def to_s          = repo ? "#{repo.path}##{number}" : "##{number}"

    # Same number; same repository when both sides know theirs.
    def matches?(record)
      return false unless record.number.to_i == number
      return true unless repo

      other = RepositoryIdentity.parse(record.repo || (record.respond_to?(:url) && record.url))
      other.nil? || other == repo
    end

    def ==(other) = other.is_a?(PullRequestReference) && key == other.key
    alias eql? ==
    def hash = key.hash
  end
end
