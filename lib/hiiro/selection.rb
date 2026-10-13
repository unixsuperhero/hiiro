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

    # One item passes through; several open the shared picker named picker on
    # a terminal and raise Ambiguous otherwise. An id is 'store:key'; the store
    # and key are the item's identity, the title only its label. nil when
    # nothing matches or the pick was cancelled.
    def pick(items, picker:, tty: $stdin.tty?, hiiro: nil)
      return nil if items.empty?
      return items.first if items.one?
      raise Ambiguous, items unless tty

      offered = items.map do |item|
        store, key = item.id.split(':', 2)
        Picker.saved_item(store: store, id: key, name: item.title, target: item.open_target, record: item)
      end
      Picker.choose(picker, offered, family: :saved, hiiro: hiiro)&.value
    end

    def open(item) = open_target(item.open_target)
    def copy(item) = copy_text(item.copy_text)

    # The macOS opener; true when it accepted the target.
    def open_target(target) = system('open', target) == true
    def copy_text(text) = Clipboard.copy_text(text)
  end
end
