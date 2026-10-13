class Hiiro
  # Select, open, and copy for saved information that lives in different
  # stores: bookmarks (SQLite), Obsidian notes (vault files, obsidian:// URIs),
  # and Portfolio documents (its HTTP API). Each command builds Items from its
  # own records; the store and its resolution rules stay with the command.
  #
  #   Item{ id: 'portfolio:42', title: 'Plan [doc #42]', open_target: 'http://127.0.0.1:4387/d/42',
  #         copy_text: 'http://127.0.0.1:4387/d/42', record: { 'id' => 42, ... } }
  module Selection
    Item = Struct.new(:id, :title, :open_target, :copy_text, :record, keyword_init: true)

    class Ambiguous < Error
      def initialize(items)
        super(items.map { |item| "  #{item.title}" }.join("\n"))
      end
    end

    module_function

    # One item passes through; several open the fuzzy finder on a terminal and
    # raise Ambiguous otherwise. nil when nothing matches or the pick was cancelled.
    def pick(items, tty: $stdin.tty?, finder: Fuzzyfind)
      return nil if items.empty?
      return items.first if items.one?
      raise Ambiguous, items unless tty

      index = finder.select_index(items.map(&:title))
      index && items[index]
    end

    def open(item) = open_target(item.open_target)
    def copy(item) = copy_text(item.copy_text)

    # The macOS opener; true when it accepted the target.
    def open_target(target) = system('open', target) == true
    def copy_text(text) = Clipboard.copy_text(text)
  end
end
