require 'json'

class Hiiro
  # The commands one Hiiro instance can run, derived from its registrations and
  # the executables named BIN-NAME on PATH. Dispatch, help, `edit`, completion,
  # and generated docs all read this one table; nothing here runs a candidate.
  #
  # Ownership of a token (name or alias), highest rank first:
  #   1. an external executable named BIN-TOKEN (first in PATH order)
  #   2. an inline registration named TOKEN (a re-registration replaces it)
  #   3. an inline alias TOKEN (first registration wins)
  # Every losing claim stays visible in the winner's `shadowed` list.
  class Catalog
    Claim = Struct.new(:name, :kind, :source, :alias_of, keyword_init: true) do
      def to_h = super.compact
    end

    Entry = Struct.new(:name, :kind, :source, :aliases, :shadowed, :runner, keyword_init: true) do
      def tokens = [name, *aliases]
      def params = runner.params_string
      def options_hint = runner.respond_to?(:opts_hint) ? runner.opts_hint : nil

      def arguments
        [params, options_hint].compact.reject(&:empty?).join('  ')
      end

      def to_h
        { name:, kind: kind.to_s, source:, aliases:, arguments: arguments.empty? ? nil : arguments,
          shadowed: shadowed.map(&:to_h) }
      end
    end

    Resolution = Struct.new(:query, :status, :entry, :candidates, keyword_init: true) do
      def resolved? = %i[exact prefix].include?(status)
      def ambiguous? = status == :ambiguous
    end

    attr_reader :bin_name, :entries

    # inline: Runners::Subcommand registrations in registration order.
    def initialize(bin_name, inline: [], external: true, path: Bins.path)
      @bin_name = bin_name
      @entries = []
      @tokens = {}
      build(inline, external ? external_runners(path) : [])
    end

    def resolve(query)
      word = query.to_s
      return Resolution.new(query: word, status: :none, candidates: []) if word.empty?

      if (entry = @tokens[word])
        return Resolution.new(query: word, status: :exact, entry:, candidates: [entry])
      end

      matches = @tokens.select { |token, _| token.start_with?(word) }.values.uniq
      matches = matches.reject { |entry| matches.any? { |other| other != entry && entry.name.start_with?("#{other.name}-") } }
      matches = matches.sort_by(&:name)
      case matches.size
      when 0 then Resolution.new(query: word, status: :none, candidates: [])
      when 1 then Resolution.new(query: word, status: :prefix, entry: matches.first, candidates: matches)
      else Resolution.new(query: word, status: :ambiguous, candidates: matches)
      end
    end

    # Every token that names a command and starts with the word, sorted.
    def complete(word = '')
      @tokens.keys.select { |token| token.start_with?(word.to_s) }.sort
    end

    def to_a = entries.map(&:to_h)
    def to_json(*args) = JSON.pretty_generate(to_a, *args)

    def to_markdown
      rows = entries.map do |entry|
        cells = [entry.name, entry.aliases.join(', '), entry.kind, entry.arguments, entry.source,
                 entry.shadowed.map { |claim| claim.alias_of ? "#{claim.name} (alias of #{claim.alias_of}) #{claim.source}" : claim.source }.join('<br>')]
        "| #{cells.map { |cell| cell.to_s.gsub('|', '\|') }.join(' | ')} |"
      end
      ["# #{bin_name} commands", '',
       '| Command | Aliases | Kind | Arguments | Source | Shadowed |',
       '|---------|---------|------|-----------|--------|----------|', *rows].join("\n") + "\n"
    end

    private

    def external_runners(path)
      prefix = "#{bin_name}-"
      Bins.glob("#{prefix}*", path:).map { |file| Runners::Bin.new(bin_name, file) }
    end

    def build(inline, externals)
      by_name = {}
      externals.each do |bin|
        if (winner = by_name[bin.subcommand_name])
          winner.shadowed << claim(bin)
        else
          by_name[bin.subcommand_name] = entry(bin, :external)
        end
      end
      inline.each do |sub|
        if (winner = by_name[sub.name])
          winner.shadowed << claim(sub)
        else
          by_name[sub.name] = entry(sub, :inline)
        end
      end
      @entries = by_name.values.sort_by(&:name)
      @entries.each { |entry| @tokens[entry.name] = entry }

      inline.each do |sub|
        owner = by_name[sub.name]
        next unless owner.runner.equal?(sub)

        sub.aliases.each do |name|
          if (winner = @tokens[name])
            winner.shadowed << claim(sub, name:, alias_of: sub.name)
          else
            owner.aliases << name
            @tokens[name] = owner
          end
        end
      end
    end

    def entry(runner, kind)
      Entry.new(name: runner.subcommand_name, kind:, source: runner.location, aliases: [], shadowed: [], runner:)
    end

    def claim(runner, name: runner.subcommand_name, alias_of: nil)
      Claim.new(name:, kind: runner.type == :bin ? 'external' : 'inline', source: runner.location, alias_of:)
    end
  end
end
