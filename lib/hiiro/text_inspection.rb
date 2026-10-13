class Hiiro
  # Declaration lines of Ruby files by named pattern group. Text matching, not
  # a parser. Regexes are per invocation; nothing is written to disk.
  #
  #   TextInspection.select(%w[meth att])     # => ['methods', 'attributes']
  #   TextInspection.select([])               # => ['class', 'attributes', 'methods'] (the 'iface' alias)
  #   TextInspection.select(['a'])            # raises Error: ambiguous (accessmodifiers, all, attributes)
  #   TextInspection.lines(path, %w[lets])    # => ["  let(:x) { 1 }\n"]
  #   TextInspection.register(hiiro, :iface, usage: 'Usage: h ruby iface [GROUP...] FILE...')
  module TextInspection
    GROUPS = {
      'class' => /\b(class|module)\b/,
      'attributes' => /\battr_(reader|writer|accessible)\b/,
      'methods' => /\b(def|alias(_method)?|def_delegator|O?Struct|Data)\b/,
      'accessmodifiers' => /\b(public|private|protected)\b/,
      'tests' => /\b(context|describe|it)\b/,
      'lets' => /\blet\b/,
      'hiiro' => /\b(Hiiro|(build|make|run)_child|(add|run)_(sub)?(cmd|command)|add_default)\b/
    }.freeze

    # 'iface' covers installed `h iface rb`: class|def|attr_reader|attr_writer|attr_accessible.
    ALIASES = { 'all' => GROUPS.keys, 'iface' => %w[class attributes methods] }.freeze
    DEFAULT = 'iface'

    module_function

    def names = GROUPS.keys + ALIASES.keys

    # Exact name, else a unique prefix; aliases expand to their groups.
    def resolve(word)
      return word if names.include?(word)

      matches = names.select { |name| name.start_with?(word) }
      raise Error, "Unknown group or missing file: #{word} (groups: #{names.join(', ')})" if matches.empty?
      raise Error, "Ambiguous group: #{word} (#{matches.sort.join(', ')})" if matches.length > 1

      matches.first
    end

    def select(words)
      words = [DEFAULT] if words.empty?
      words.flat_map { |word| name = resolve(word); ALIASES.fetch(name, [name]) }.uniq
    end

    def lines(path, groups)
      pattern = Regexp.union(groups.map { |group| GROUPS.fetch(group) })
      File.binread(path).each_line.select { |line| pattern.match?(line) }
    end

    # Prints every file; false when any file had no matching line (the
    # command then exits 1, as installed `h iface rb` did).
    def report(files, groups, out: $stdout)
      out.binmode
      files.map do |path|
        found = lines(path, groups)
        out.write("\n", format('  FILE: %s', path), "\n", format('  FILE: %s  ', path).gsub(/./, '='), "\n")
        found.each { |line| out.write(line.end_with?("\n") ? line : "#{line}\n") }
        out.write("\n")
        found.any?
      end.all?
    end

    def register(hiiro, name, usage:)
      hiiro.add_subcmd(name) do |*args|
        files, words = args.partition { |arg| File.file?(arg) }
        abort usage if files.empty?
        exit 1 unless TextInspection.report(files, TextInspection.select(words))
      rescue Error => e
        abort e.message
      end
    end
  end
end
