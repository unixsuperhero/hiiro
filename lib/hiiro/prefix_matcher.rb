class Hiiro
  module PrefixMatcher
    class << self
      # Find first item matching prefix
      def find(items, prefix, key: nil, &block)
        items.find { |item| matches?(item, prefix, key, &block) }
      end

      # Find all items matching prefix
      def find_all(items, prefix, key: nil, &block)
        items.select { |item| matches?(item, prefix, key, &block) }
      end

      # Resolve: prefer exact match > single prefix match > nil
      def resolve(items, prefix, key: nil, &block)
        exact = items.find { |item| extract(item, key, &block) == prefix }
        return exact if exact

        matches = find_all(items, prefix, key: key, &block)
        matches.one? ? matches.first : nil
      end

      private

      def matches?(item, prefix, key = nil, &block)
        extract(item, key, &block).to_s.start_with?(prefix.to_s)
      end

      def extract(item, key = nil, &block)
        return block.call(item) if block
        return item.send(key) if key
        item
      end
    end
  end
end
