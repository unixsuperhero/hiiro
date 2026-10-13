require 'json'
require 'set'
require_relative 'error'
require_relative 'path_pattern'

class Hiiro
  # The shared interactive picker: stable item identities, persistent
  # exclusion rules, and the editor document that changes them. The screen is
  # Hiiro::PickerScreen; rules persist through Hiiro::PickerExclusion.
  #
  #   item = Picker.item(:branch, '/src/app', 'main', label: 'main', value: 'main', name: 'main', repo: '/src/app')
  #   item.identity  # => ["branch", "/src/app", "main"]
  #   Picker.choose('branches', items, family: :branch)   # => Item, [Item] (multi:), or nil
  module Picker
    # The fields a rule may match for each family. `id` (the identity) is
    # matched only by exact rules. `path` values are relative to a stated
    # base, use `/`, and never start with `./`.
    FAMILIES = {
      'command' => %w[name kind path],
      'file' => %w[path name base],
      'task' => %w[id name path],
      'project' => %w[name path],
      'branch' => %w[name repo],
      'pr' => %w[number repo branch name],
      'saved' => %w[store id name target],
    }.freeze
    MODES = %w[exact literal substring regex glob extglob].freeze
    SCOPES = %w[picker task project global].freeze
    REGEX_TIMEOUT = 1.0

    class Invalid < Error; end

    Item = Struct.new(:identity, :label, :fields, :value, keyword_init: true) do
      def family = identity.first
      def to_s = label
      def field(name) = fields[name]
    end

    def self.item(family, *identity, label:, value: nil, **fields)
      values = fields.to_h { |name, field| [name.to_s, field.to_s] }
      values['path'] = normalize_path(values['path']) if values.key?('path')
      Item.new(identity: [family.to_s, *identity.map(&:to_s)], label: label.to_s.tr("\t\n", '  '), fields: values, value: value)
    end

    def self.normalize_path(path)
      path.to_s.gsub(%r{/+}, '/').sub(%r{\A(?:\./)+}, '')
    end

    # Identity by catalog provenance: kind, name, and the defining file.
    def self.command_item(entry)
      source = entry.source.to_s.sub(/:\d+\z/, '')
      item(:command, entry.kind, entry.name, source, label: "#{entry.name}  #{entry.kind}  #{source}", value: entry,
                                                     name: entry.name, kind: entry.kind, path: source)
    end

    # Identity is the base plus the path relative to it; outside the base the
    # base is / and the path is absolute without its leading slash.
    def self.file_item(path, base:, label: nil, value: path)
      base = real_path(base)
      full = real_path(path)
      inside = full.start_with?("#{base}/")
      relative = inside ? full.delete_prefix("#{base}/") : full.delete_prefix('/')
      base = '/' unless inside
      item(:file, base, relative, label: label || (inside ? relative : full), value: value, path: relative, name: File.basename(full), base: base)
    end

    def self.real_path(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end

    # Durable task ID; a task without one (a subtask's synthetic main) by name.
    def self.task_item(task, label: nil, value: task)
      tree = task.respond_to?(:tree) ? task.tree : (task.tree_name if task.respond_to?(:tree_name))
      item(:task, task.id ? task.id.to_s : "name:#{task.name}", label: label || task.name, value: value,
                                                              id: task.id, name: task.name, path: tree)
    end

    def self.project_item(name, path, label: nil, value: [name, path])
      item(:project, name, label: label || name, value: value, name: name, path: path)
    end

    # The repository a branch belongs to: the main checkout's directory, so
    # every worktree of one repository gives its branches the same identity.
    def self.git_repository(dir = Dir.pwd)
      require 'open3'
      out, status = Open3.capture2('git', '-C', dir, 'rev-parse', '--path-format=absolute', '--git-common-dir', err: File::NULL)
      return real_path(dir) unless status.success?

      common = real_path(out.strip)
      File.basename(common) == '.git' ? File.dirname(common) : common
    end

    def self.branch_item(name, repo:, label: nil, value: name)
      item(:branch, repo, name, label: label || name, value: value, name: name, repo: repo)
    end

    def self.pr_item(number:, repo:, branch: nil, title: nil, label: nil, value: nil)
      item(:pr, repo, number, label: label || "##{number} [#{branch}] #{title}", value: value,
                              number: number, repo: repo, branch: branch, name: title)
    end

    # A Git::Pr or PinnedPr, qualified by its repository.
    def self.pr_record_item(pr, label: nil, value: pr)
      repo = pr.reference&.repo&.path || pr.repo.to_s
      pr_item(number: pr.number, repo: repo, branch: pr.head_branch, title: pr.title, label: label, value: value)
    end

    def self.saved_item(store:, id:, name:, target: nil, label: nil, record: nil)
      item(:saved, store, id, label: label || name, value: record, store: store, id: id, name: name, target: target)
    end

    def self.task_chooser(name = 'tasks', hiiro: nil)
      chooser(name, family: :task, hiiro: hiiro) { |task, label| task_item(task, label: label) }
    end

    # The task and project a picker runs in. Task and project rules apply only
    # where these match; picker-local and global rules apply everywhere.
    Context = Struct.new(:task_id, :task_name, :project, keyword_init: true) do
      def self.none = new

      def self.for_task(task, project: nil)
        task ? new(task_id: task.id.to_s, task_name: task.name, project: project) : new(project: project)
      end

      # The task CurrentTask infers for cwd (never a chooser, never a pin
      # write) and the project whose directory holds cwd.
      def self.detect(cwd: Dir.pwd)
        task = begin
          CurrentTask.new(herdr: -> { Hiiro::Herdr.client }, cwd: cwd, pin: false).resolve
        rescue StandardError
          nil
        end
        project = begin
          Projects.new.all.select { |_, path| TaskLocation.contains?(File.expand_path(path), cwd) }.max_by { |_, path| path.length }&.first
        rescue StandardError
          nil
        end
        for_task(task, project: project)
      end

      def scope_key(scope)
        case scope
        when 'task' then task_id
        when 'project' then project
        end
      end

      def available?(scope) = %w[picker global].include?(scope) || !scope_key(scope).nil?

      def describe(scope)
        case scope
        when 'picker' then 'this picker everywhere'
        when 'task' then task_id ? "task #{task_id} #{task_name}".strip : 'no current task'
        when 'project' then project ? "project #{project}" : 'no current project'
        when 'global' then 'every picker'
        end
      end
    end

    # One exclusion. exact matches the whole identity (pattern is its JSON);
    # literal is equality, substring containment, regex a Ruby (Onigmo)
    # unanchored search, glob and extglob PathPattern full matches. All modes
    # are case-sensitive; a regex may use (?i).
    Rule = Struct.new(:id, :picker, :scope, :scope_key, :mode, :field, :pattern, :label, :created_at, keyword_init: true) do
      def validate!(family)
        raise Invalid, "unknown scope #{scope.inspect}; use #{SCOPES.join(', ')}" unless SCOPES.include?(scope)
        raise Invalid, "unknown mode #{mode.inspect}; use #{MODES.join(', ')}" unless MODES.include?(mode)
        raise Invalid, "#{mode} rule needs a non-empty text pattern" unless pattern.is_a?(String) && !pattern.empty?

        fields = FAMILIES.fetch(family)
        if mode == 'exact'
          raise Invalid, "exact rules match field id, not #{field.inspect}" unless field == 'id'
        elsif !fields.include?(field)
          raise Invalid, "unknown field #{field.inspect} for #{family} items; use #{fields.join(', ')}"
        end
        matcher
        self
      end

      def matches?(item)
        return item.identity == matcher if mode == 'exact'

        value = item.field(field)
        return false if value.nil?

        case mode
        when 'literal' then value == normalized_pattern
        when 'substring' then value.include?(pattern)
        else matcher.match?(value)
        end
      end

      def key = [scope, scope_key, mode, field, pattern]

      def describe
        where = scope == 'global' ? 'global' : [scope, scope_key].compact.join(' ')
        text = mode == 'exact' ? "exact #{label || pattern}" : "#{mode} #{field} #{pattern}"
        "#{text} [#{where}]"
      end

      private

      def normalized_pattern = field == 'path' ? Picker.normalize_path(pattern) : pattern

      def matcher
        @matcher ||= case mode
        when 'exact' then parse_identity
        when 'regex' then compile_regex
        when 'glob', 'extglob' then compile_glob
        end
      end

      def parse_identity
        identity = JSON.parse(pattern)
        raise Invalid, "exact pattern must be a JSON list of strings: #{pattern}" unless identity.is_a?(Array) && identity.all?(String)

        identity
      rescue JSON::ParserError
        raise Invalid, "exact pattern must be a JSON list of strings: #{pattern}"
      end

      def compile_regex
        Regexp.new(pattern, timeout: REGEX_TIMEOUT)
      rescue RegexpError => error
        raise Invalid, "invalid regex #{pattern.inspect}: #{error.message}"
      end

      def compile_glob
        PathPattern.compile(normalized_pattern, extglob: mode == 'extglob')
      rescue PathPattern::Invalid => error
        raise Invalid, "invalid #{mode} #{pattern.inspect}: #{error.message}"
      end
    end

    Change = Struct.new(:add, :remove, keyword_init: true) do
      def empty? = add.empty? && remove.empty?
    end

    # The text the editor shows: a snapshot of the listed items (identities;
    # labels are comments) and the rules that apply here. Deleting an item line
    # adds an exact rule for it; items not in the snapshot are never excluded.
    class Document
      attr_reader :picker, :family, :snapshot, :rules, :context

      def initialize(picker:, family:, snapshot:, rules:, context:)
        @picker = picker
        @family = family
        @snapshot = snapshot
        @rules = rules
        @context = context
      end

      def default_scope = context.task_id ? 'task' : 'picker'

      def text
        scopes = SCOPES.map { |scope| "#{scope} (#{context.describe(scope)})" }.join(' | ')
        lines = [
          "# Picker #{picker} (#{family} items). Save and quit to preview; nothing is saved until you confirm.",
          '# Delete an item line to exclude that item. Only the items listed here can be excluded',
          '# this way; items filtered out, already excluded, or added later are left alone.',
          "# scope (for new rules): #{scopes}",
          "# modes: literal, substring, regex, glob, extglob on fields #{FAMILIES.fetch(family).join(', ')}; exact on field id",
          "# example: - #{FAMILIES.fetch(family).include?('path') ? '{mode: glob, field: path, pattern: "**/*.bak"}' : '{mode: glob, field: name, pattern: "draft-*"}'}",
          "scope: #{default_scope}",
          'items:',
          *snapshot.map { |item| "- #{JSON.generate(item.identity)}  # #{item.label}" },
          'rules:',
          *rules.map { |rule| rule_line(rule) },
        ]
        lines.join("\n") + "\n"
      end

      # The rules to add and remove, or Invalid. Nothing is written here.
      def change(parsed)
        raise Invalid, 'the document must be a mapping with scope, items, and rules' unless parsed.is_a?(Hash)

        unknown = parsed.keys - %w[scope items rules]
        raise Invalid, "unknown keys: #{unknown.join(', ')}" unless unknown.empty?

        scope = scope!(parsed.fetch('scope', default_scope))
        kept = items!(parsed['items'])
        edited = Array(parsed['rules'] || [])
        raise Invalid, 'rules must be a list' unless parsed['rules'].nil? || parsed['rules'].is_a?(Array)

        add = []
        remove = []
        seen = Set.new
        by_id = rules.to_h { |rule| [rule.id, rule] }
        edited.each_with_index do |entry, index|
          rule, id = rule!(entry, index, scope)
          if id
            original = by_id[id] || raise(Invalid, "rule #{index + 1}: no rule with id #{id} here")
            raise Invalid, "rule #{index + 1}: id #{id} is listed twice" unless seen.add?(id)
            next if original.key == rule.key

            remove << original
          end
          add << rule
        end
        remove.concat(rules.reject { |rule| seen.include?(rule.id) })

        existing = (rules - remove + add).map(&:key)
        snapshot.reject { |item| kept.include?(item.identity) }.uniq(&:identity).each do |item|
          rule = exact_rule(item, scope)
          next if existing.include?(rule.key)

          add << rule
          existing << rule.key
        end
        Change.new(add: add, remove: remove)
      end

      def exact_rule(item, scope)
        Rule.new(picker: picker, scope: scope, scope_key: context.scope_key(scope), mode: 'exact', field: 'id',
                 pattern: JSON.generate(item.identity), label: item.label).validate!(family)
      end

      private

      def rule_line(rule)
        fields = { 'id' => rule.id, 'scope' => rule.scope, 'mode' => rule.mode, 'field' => rule.field }
        body = fields.map { |name, value| "#{name}: #{value}" }.join(', ')
        line = "- {#{body}, pattern: #{JSON.generate(rule.pattern)}}"
        rule.mode == 'exact' && rule.label ? "#{line}  # #{rule.label}" : line
      end

      def scope!(scope)
        scope = scope.to_s
        raise Invalid, "unknown scope #{scope.inspect}; use #{SCOPES.join(', ')}" unless SCOPES.include?(scope)
        raise Invalid, "scope #{scope} is not available: #{context.describe(scope)}" unless context.available?(scope)

        scope
      end

      def items!(entries)
        return Set.new if entries.nil?
        raise Invalid, 'items must be a list' unless entries.is_a?(Array)

        known = snapshot.map(&:identity).to_set
        entries.each_with_index.with_object(Set.new) do |(entry, index), kept|
          identity = entry.is_a?(Array) ? entry.map(&:to_s) : nil
          raise Invalid, "item #{index + 1}: #{entry.inspect} is not one of the listed items" unless identity && known.include?(identity)

          kept << identity
        end
      end

      def rule!(entry, index, default)
        raise Invalid, "rule #{index + 1} must be a mapping" unless entry.is_a?(Hash)

        unknown = entry.keys - %w[id scope mode field pattern]
        raise Invalid, "rule #{index + 1}: unknown keys #{unknown.join(', ')}" unless unknown.empty?

        scope = scope!(entry.fetch('scope', default))
        mode = entry['mode'].to_s
        rule = Rule.new(picker: picker, scope: scope, scope_key: context.scope_key(scope), mode: mode,
                        field: entry.fetch('field', mode == 'exact' ? 'id' : nil).to_s, pattern: entry['pattern'])
        rule.label = rules.find { |old| old.id == entry['id'] }&.label if mode == 'exact'
        rule.validate!(family)
        [rule, entry['id']]
      rescue Invalid => error
        raise Invalid, error.message.start_with?('rule ') ? error.message : "rule #{index + 1}: #{error.message}"
      end
    end

    # Opens the editor on the document text: an EditedDocument, plus a durable
    # copy of the text when it has to be kept for recovery.
    class Editor
      def initialize(hiiro = nil)
        @hiiro = hiiro
      end

      def call(text)
        @input&.cleanup
        @input = InputFile.yaml_file(hiiro: host, content: text, prefix: 'picker-')
        @input.edit.document
      end

      def keep = @input&.keep

      private

      def host = @hiiro ||= Hiiro.new('h')
    end

    def self.choose(name, items, family:, context: nil, multi: false, hiiro: nil, store: nil, editor: nil)
      family = family.to_s
      raise ArgumentError, "unknown picker family #{family}" unless FAMILIES.key?(family)
      raise Error, "Choosing from #{name} needs a terminal" unless $stdin.tty?

      result = PickerScreen.new(name: name, family: family, items: items, context: context || Context.detect,
                                multi: multi, store: store || PickerExclusion, editor: editor || Editor.new(hiiro)).run
      result || nil
    end

    # A chooser for code that hands a { label => value } mapping to a callable.
    # build turns each value (and its label) into an Item; the chosen value
    # comes back, never a label.
    def self.chooser(name, family:, context: nil, hiiro: nil, &build)
      lambda do |mapping|
        items = mapping.map { |label, value| build.call(value, label) }
        choose(name, items, family: family, context: context, hiiro: hiiro)&.value
      end
    end
  end
end
