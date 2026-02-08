class Hiiro
  class PrefixMatcher
    class << self
      def find(items, prefix, key: nil, &block)
        new(items, key, &block).find(prefix)
      end

      def find_all(items, prefix, key: nil, &block)
        new(items, key, &block).find_all(prefix)
      end

      def resolve(items, prefix, key: nil, &block)
        new(items, key, &block).resolve(prefix)
      end

      def find_path(items, prefix, key: nil, &block)
        new(items, key, &block).find_path(prefix)
      end

      def find_all_paths(items, prefix, key: nil, &block)
        new(items, key, &block).find_all_paths(prefix)
      end

      def resolve_path(items, prefix, key: nil, &block)
        new(items, key, &block).resolve_path(prefix)
      end
    end

    attr_reader :original_items, :key, :block

    def initialize(items, key = nil, &block)
      @original_items = items
      @key = key
      @block = block
    end

    def all_items(key = nil, &block)
      use_key = key.nil? && !block_given? ? @key : key
      use_block = key.nil? && !block_given? ? @block : block

      @all_items_cache ||= {}
      cache_key = [use_key, use_block].hash

      @all_items_cache[cache_key] ||= original_items.map { |item|
        Item.new(
          item: item,
          extracted_item: extract(item, use_key, &use_block),
          key: use_key,
          block: use_block
        )
      }
    end

    def search(prefix, key = nil, &block)
      Result.new(
        matcher: self,
        all_items: all_items(key, &block),
        prefix: prefix,
        key: key || @key,
        block: block || @block
      )
    end

    def find(prefix, key = nil, &block)
      search(prefix, key, &block)
    end

    def find_all(prefix, key = nil, &block)
      search(prefix, key, &block)
    end

    def resolve(prefix, key = nil, &block)
      search(prefix, key, &block)
    end

    def find_path(prefix, key = nil, &block)
      search_path(prefix, key, &block)
    end

    def find_all_paths(prefix, key = nil, &block)
      search_path(prefix, key, &block)
    end

    def resolve_path(prefix, key = nil, &block)
      search_path(prefix, key, &block)
    end

    def search_path(prefix, key = nil, &block)
      PathResult.new(
        matcher: self,
        all_items: all_items(key, &block),
        prefix: prefix,
        key: key || @key,
        block: block || @block
      )
    end

    private

    def matches?(item, prefix)
      item.to_s.start_with?(prefix.to_s)
    end

    def extract(item, key = nil, &block)
      return block.call(item) if block
      return item.send(key) if key
      item
    end

    class Item
      attr_reader :item, :extracted_item, :key, :block

      def initialize(item:, extracted_item:, key: nil, block: nil)
        @item = item
        @extracted_item = extracted_item
        @key = key
        @block = block
      end
    end

    class Result
      attr_reader :matcher, :all_items, :key, :block, :prefix

      def initialize(matcher:, all_items:, prefix:, key: nil, block: nil)
        @matcher = matcher
        @all_items = all_items
        @prefix = prefix
        @key = key
        @block = block
      end

      def matches
        @matches ||= all_items.select { |item| item.extracted_item.to_s.start_with?(prefix.to_s) }
      end

      def count
        matches.count
      end

      def ambiguous?
        count > 1
      end

      def exact_match
        all_items.find { |item| item.extracted_item == prefix }
      end

      def match
        one? ? matches.first : nil
      end

      def match?
        matches.any?
      end

      def exact?
        !exact_match.nil?
      end

      def one?
        count == 1
      end

      # Returns item for resolve semantics: exact match, or single match, otherwise nil
      def resolved
        exact_match || match
      end

      # Returns the first matching item (for find semantics)
      def first
        matches.first
      end
    end

    class PathResult
      attr_reader :matcher, :all_items, :key, :block, :prefix

      def initialize(matcher:, all_items:, prefix:, key: nil, block: nil)
        @matcher = matcher
        @all_items = all_items
        @prefix = prefix
        @key = key
        @block = block
      end

      def matches
        @matches ||= begin
          prefixes = prefix.to_s.split('/')

          items_with_paths = all_items.map { |item|
            [item, item.extracted_item.to_s.split('/')]
          }

          prefixes.each_with_index do |seg, i|
            items_with_paths = items_with_paths.select { |_, path| path[i]&.start_with?(seg) }
          end

          items_with_paths.map(&:first)
        end
      end

      def count
        matches.count
      end

      def ambiguous?
        count > 1
      end

      def exact_match
        all_items.find { |item| item.extracted_item == prefix }
      end

      def match
        one? ? matches.first : nil
      end

      def match?
        matches.any?
      end

      def exact?
        !exact_match.nil?
      end

      def one?
        count == 1
      end

      # Returns item for resolve semantics: exact match, or single match, otherwise nil
      def resolved
        exact_match || match
      end

      # Returns the first matching item (for find semantics)
      def first
        matches.first
      end
    end
  end
end
