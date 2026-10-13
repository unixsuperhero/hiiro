require 'fileutils'
require 'json'
require 'tmpdir'

class Hiiro
  class Git
    # git in one repository through CommandSpecification/Shell.execute. Every
    # call sets GIT_OPTIONAL_LOCKS=0 so inspection never refreshes the real index.
    class IndexGit
      Failed = Class.new(Hiiro::Error) do
        attr_reader :result

        def initialize(result)
          @result = result
          detail = result.stderr.to_s.strip
          super("#{result.command} failed (exit #{result.exit_code})#{detail.empty? ? '' : ": #{detail}"}")
        end
      end

      attr_reader :root

      def self.at(dir)
        result = new(dir).run('rev-parse', '--show-toplevel')
        result.success? ? new(result.stdout.chomp) : nil
      end

      def initialize(root)
        @root = root
      end

      def run(*args, index: nil, stdin: '')
        env = { 'GIT_OPTIONAL_LOCKS' => '0' }
        env['GIT_INDEX_FILE'] = index if index
        Shell.execute(CommandSpecification.new('git', *args, env: env, cwd: root), stdin_data: stdin)
      end

      def run!(*args, **options)
        result = run(*args, **options)
        raise Failed, result unless result.success?

        result
      end

      def head
        result = run('rev-parse', '--verify', '--quiet', 'HEAD^{commit}')
        result.success? ? result.stdout.chomp : nil
      end

      def index_path
        run!('rev-parse', '--path-format=absolute', '--git-path', 'index').stdout.chomp
      end

      def empty_tree
        run!('hash-object', '-t', 'tree', '/dev/null').stdout.chomp
      end

      # A disposable index seeded with a copy of the real one, removed afterwards.
      def with_index_copy
        Dir.mktmpdir('hiiro-index-') do |dir|
          copy = File.join(dir, 'index')
          FileUtils.cp(index_path, copy) if File.exist?(index_path)
          yield copy
        end
      end
    end

    # One changed path. A rename carries its source; both paths move together.
    Change = Data.define(:path, :status, :source, :staged, :unstaged, :untracked, :binary) do
      def paths = [path, source].compact
      def partial? = staged && unstaged

      def to_h
        { 'path' => path, 'status' => status, 'source' => source, 'staged' => staged,
          'unstaged' => unstaged, 'untracked' => untracked, 'binary' => binary }
      end
    end

    # Everything a commit plan must cover, read without touching the real index:
    # status runs on one copy of it, `add -A` + diff on another.
    class ChangeSet
      MAX_DIFF_BYTES = 120_000

      Unmerged = Class.new(Hiiro::Error)

      attr_reader :changes, :diff, :fingerprint

      def self.capture(git)
        head = git.head
        base = head || git.empty_tree
        flags, index_tree = git.with_index_copy do |copy|
          status = git.run!('status', '--porcelain=v2', '-z', '--untracked-files=all', '--no-renames', index: copy)
          [status_flags(status.stdout), git.run!('write-tree', index: copy).stdout.chomp]
        end

        git.with_index_copy do |copy|
          git.run!('add', '-A', index: copy)
          names = git.run!('diff', '--cached', '--name-status', '-z', '-M', base, index: copy).stdout
          numstat = git.run!('diff', '--cached', '--numstat', '-z', '--no-renames', base, index: copy).stdout
          diff = git.run!('diff', '--cached', '-M', base, index: copy).stdout
          worktree_tree = git.run!('write-tree', index: copy).stdout.chomp
          binary = binary_paths(numstat)
          changes = name_status(names).map do |status, path, source|
            own = flags.fetch(path, {})
            src = source ? flags.fetch(source, {}) : {}
            Change.new(path: path, status: status, source: source,
                       staged: !!(own[:staged] || src[:staged]), unstaged: !!(own[:unstaged] || src[:unstaged]),
                       untracked: !!own[:untracked], binary: binary.include?(path))
          end
          new(changes, diff, { head: head, index: index_tree, worktree: worktree_tree })
        end
      end

      # `status --porcelain=v2 -z --no-renames`: one record per path.
      def self.status_flags(output)
        output.split("\0").each_with_object({}) do |record, flags|
          case record[0]
          when '1'
            xy = record[2, 2]
            path = record.split(' ', 9).last
            flags[path] = { staged: xy[0] != '.', unstaged: xy[1] != '.' }
          when '?'
            flags[record[2..]] = { untracked: true, unstaged: true }
          when 'u'
            raise Unmerged, "Unmerged path #{record.split(' ', 11).last.inspect}; resolve the merge first."
          end
        end
      end

      # `diff --name-status -z -M`: STATUS\0PATH\0, or R###\0SOURCE\0PATH\0.
      def self.name_status(output)
        fields = output.split("\0")
        entries = []
        until fields.empty?
          status = fields.shift
          if status.start_with?('R', 'C')
            source = fields.shift
            entries << [status[0], fields.shift, source]
          else
            entries << [status[0], fields.shift, nil]
          end
        end
        entries
      end

      def self.binary_paths(output)
        output.split("\0").filter_map { |record| record.split("\t", 3).last if record.start_with?("-\t-\t") }
      end

      def initialize(changes, diff, fingerprint)
        @changes = changes
        @diff = diff
        @fingerprint = fingerprint
      end

      def empty? = changes.empty?
      def paths = changes.map(&:path)
      def find(path) = changes.find { |change| change.path == path }
      def partial = changes.select(&:partial?)
      def diff_truncated? = diff.bytesize > MAX_DIFF_BYTES

      # One JSON object per change: the exact paths a planner must use.
      def listing
        changes.map do |change|
          JSON.generate({ 'path' => change.path, 'status' => change.status, 'from' => change.source,
                          'binary' => change.binary || nil }.compact)
        end.join("\n")
      end

      def prompt_diff
        diff.byteslice(0, MAX_DIFF_BYTES).force_encoding(Encoding::UTF_8).scrub
      end
    end

    # The planner's groups, accepted only through CommitPlan.validate.
    class CommitPlan
      Group = Data.define(:message, :paths) do
        def subject = message.lines.first.to_s.chomp
      end

      Validation = Data.define(:groups, :shape, :unknown, :duplicate, :missing) do
        def valid? = [shape, unknown, duplicate, missing].all?(&:empty?)
        def plan = valid? ? CommitPlan.new(groups) : nil

        def errors
          [*shape,
           *(unknown.empty? ? [] : ["unknown paths: #{unknown.map(&:inspect).join(', ')}"]),
           *(duplicate.empty? ? [] : ["paths assigned more than once: #{duplicate.map(&:inspect).join(', ')}"]),
           *(missing.empty? ? [] : ["paths not assigned: #{missing.map(&:inspect).join(', ')}"])]
        end
      end

      # Runs before any mutation. The planner may wrap the array in fences or prose.
      def self.validate(raw, change_set)
        text = raw.to_s.strip.gsub(/\A```(?:json)?\n?/, '').gsub(/```\z/, '').strip
        start = text.index('[')
        finish = text.rindex(']')
        return shape_error('no JSON array in planner output') unless start && finish

        data = begin
          JSON.parse(text[start..finish])
        rescue JSON::ParserError => e
          return shape_error("planner output is not valid JSON: #{e.message.lines.first.strip}")
        end
        return shape_error('the plan has no commits') if data.empty?

        shape = []
        groups = data.each_with_index.filter_map do |entry, i|
          unless entry.is_a?(Hash)
            shape << "commit #{i + 1} is not an object"
            next
          end
          message = entry['message']
          files = entry['files']
          shape << "commit #{i + 1} has no message" unless message.is_a?(String) && !message.strip.empty?
          unless files.is_a?(Array) && !files.empty? && files.all?(String)
            shape << "commit #{i + 1} needs a nonempty \"files\" array of strings"
            next
          end
          Group.new(message: message.to_s.strip, paths: files)
        end

        assigned = groups.flat_map(&:paths)
        known = change_set.paths
        Validation.new(groups: groups, shape: shape,
                       unknown: (assigned - known).uniq,
                       duplicate: assigned.tally.select { |_, n| n > 1 }.keys,
                       missing: shape.empty? ? known - assigned : [])
      end

      def self.shape_error(message)
        Validation.new(groups: [], shape: [message], unknown: [], duplicate: [], missing: [])
      end

      attr_reader :groups

      def initialize(groups)
        @groups = groups
      end
    end

    # Asks the planner command for groups. The prompt is the grouping strategy.
    class CommitPlanner
      Failed = Class.new(Hiiro::Error)

      attr_reader :command

      def initialize(model:)
        @command = ['claude', '-p', '--model', model]
      end

      def call(change_set, cwd:)
        result = Shell.execute(CommandSpecification.new(*command, cwd: cwd), stdin_data: prompt(change_set))
        unless result.success?
          detail = result.stderr.to_s.strip
          raise Failed, "planner `#{result.command}` failed (#{ProcessOutcome.from_status(result.status)})#{detail.empty? ? '' : ": #{detail}"}"
        end

        result.stdout.force_encoding(Encoding::UTF_8)
      rescue SystemCallError => e
        raise Failed, "planner `#{command.join(' ')}` could not start: #{e.message}"
      end

      def prompt(change_set)
        <<~PROMPT
          You are organizing a git working tree's uncommitted changes into a series of
          logical commits.

          Respond with ONLY a JSON array (no prose, no markdown fences). Each element:
            { "message": "<commit message>", "files": ["path/one", "path/two"] }

          Rules:
          - Every changed file listed below must appear in exactly ONE commit.
          - Group by logical concern (feature, fix, refactor, docs, tests, config,
            chore) rather than by directory.
          - Order the commits so that prerequisite changes come first.
          - "message" is a Conventional-Commits-style subject line in the imperative
            mood (e.g. "fix: handle empty diff"). Add a blank line + short body only
            when it genuinely helps.
          - Use the exact "path" values shown below. A rename's "from" path moves
            with it; do not list it separately.

          Changed files (one JSON object per line):
          #{change_set.listing}

          Unified diff#{change_set.diff_truncated? ? ' (TRUNCATED — some changes omitted)' : ''}:
          #{change_set.prompt_diff}
        PROMPT
      end
    end

    # Commits each group from its own index seeded with HEAD, then points the
    # real index at HEAD for just those paths. Stops at the first failure.
    class CommitExecution
      Step = Data.define(:number, :group, :sha)
      Failure = Data.define(:number, :group, :operation, :message)
      Outcome = Data.define(:completed, :failure) do
        def success? = failure.nil?
      end

      def initialize(git, change_set)
        @git = git
        @change_set = change_set
      end

      def call(plan, &progress)
        completed = []
        plan.groups.each_with_index do |group, i|
          number = i + 1
          paths = group.paths.flat_map { |path| @change_set.find(path).paths }
          operation = 'add'
          begin
            Dir.mktmpdir('hiiro-commit-') do |dir|
              index = File.join(dir, 'index')
              head = @git.head
              @git.run!('read-tree', head, index: index) if head
              @git.run!('--literal-pathspecs', 'add', '-A', '--', *paths, index: index)
              operation = 'commit'
              @git.run!('commit', '--quiet', '-F', '-', index: index, stdin: group.message)
            end
            operation = 'update index'
            reconcile(paths)
          rescue IndexGit::Failed => e
            failure = Failure.new(number: number, group: group, operation: operation, message: e.message)
            progress&.call(failure)
            return Outcome.new(completed: completed, failure: failure)
          end
          step = Step.new(number: number, group: group, sha: @git.head)
          completed << step
          progress&.call(step)
        end
        Outcome.new(completed: completed, failure: nil)
      end

      private

      # The committed paths now match HEAD; every other path keeps the user's staging.
      def reconcile(paths)
        head = @git.head
        listed = @git.run!('ls-tree', '-r', '-z', '--full-tree', head, '--', *paths).stdout.split("\0")
        entries = listed.to_h { |line| [line.split("\t", 2).last, line] }
        zero = '0' * head.length
        info = paths.map { |path| entries.fetch(path) { "0 #{zero}\t#{path}" } }
        @git.run!('update-index', '-z', '--index-info', stdin: info.map { |line| "#{line}\0" }.join)
      end
    end
  end
end
