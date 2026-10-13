class Hiiro
  # Commits read from `git log` and the shared `commits` picker that
  # h commit select and h sha select choose from.
  #
  #   commits = CommitLog.read('-n', '50', '--', 'lib')   # extra args go to git log as argv
  #   commits.first  # => Commit{ sha: "9fceb02…", short: "9fceb02", subject: "Fix x", decorations: "HEAD -> main", repo: "/src/app" }
  #   CommitLog.choose(commits, decorate: true)           # => a Commit, or nil when cancelled
  module CommitLog
    PICKER = 'commits'
    # Full SHA, abbreviated SHA, ref names, subject: unit-separated fields,
    # NUL-terminated records (-z).
    FORMAT = '--format=%H%x1f%h%x1f%D%x1f%s'

    Commit = Struct.new(:sha, :short, :subject, :decorations, :repo, keyword_init: true) do
      # The `git log --oneline` line, with `--decorate` ref names when asked.
      def line(decorate: false)
        refs = decorate && !decorations.empty? ? " (#{decorations})" : ''
        "#{short}#{refs} #{subject}"
      end

      def picker_item(decorate: false)
        Picker.commit_item(sha, repo: repo, subject: subject, decorations: decorations, label: line(decorate: decorate), value: self)
      end
    end

    module_function

    # git's own errors pass through to stderr; a failing git reads as no commits.
    def read(*log_args, dir: Dir.pwd)
      out = IO.popen(['git', '-C', dir, 'log', '-z', FORMAT, *log_args], &:read)
      return [] unless $?.success?

      repo = Picker.git_repository(dir)
      out.split("\0").map do |record|
        sha, short, decorations, subject = record.delete_prefix("\n").split("\x1f", 4)
        Commit.new(sha: sha, short: short, subject: subject.to_s, decorations: decorations.to_s, repo: repo)
      end
    end

    def choose(commits, decorate: false, hiiro: nil)
      Picker.choose(PICKER, commits.map { |commit| commit.picker_item(decorate: decorate) }, family: :commit, hiiro: hiiro)&.value
    end
  end
end
