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

    def items(key = nil, &block)
      if key.nil? && !block_given?
        @items ||= original_items.map { |item| extract(item, @key, &@block) }
      else
        original_items.map { |item| extract(item, key, &block) }
      end
    end

    def find(prefix, key = nil, &block)
      original_items.zip(items(key, &block)).find { |_, extracted| matches?(extracted, prefix) }&.first
    end

    def find_all(prefix, key = nil, &block)
      original_items.zip(items(key, &block)).select { |_, extracted| matches?(extracted, prefix) }.map(&:first)
    end

    def resolve(prefix, key = nil, &block)
      pairs = original_items.zip(items(key, &block))

      exact = pairs.find { |_, extracted| extracted == prefix }
      return exact.first if exact

      matches = pairs.select { |_, extracted| matches?(extracted, prefix) }
      matches.one? ? matches.first.first : nil
    end

    def find_path(prefix, key = nil, &block)
      matching_path_pairs(prefix, key, &block).first&.first
    end

    def find_all_paths(prefix, key = nil, &block)
      matching_path_pairs(prefix, key, &block).map(&:first)
    end

    def resolve_path(prefix, key = nil, &block)
      matches = matching_path_pairs(prefix, key, &block)
      return nil if matches.empty?
      return matches.first.first if matches.one?

      exact = matches.find { |_, path| path == prefix }
      exact&.first
    end

    private

    def matching_path_pairs(prefix, key = nil, &block)
      prefixes = prefix.to_s.split('/')

      pairs = original_items.zip(items(key, &block)).map { |item, extracted|
        [item, extracted.to_s.split('/')]
      }

      prefixes.each_with_index do |seg, i|
        pairs = pairs.select { |_, path| path[i]&.start_with?(seg) }
      end

      pairs.map { |item, path| [item, path.join('/')] }
    end

    def matches?(item, prefix)
      item.to_s.start_with?(prefix.to_s)
    end

    def extract(item, key = nil, &block)
      return block.call(item) if block
      return item.send(key) if key
      item
    end
  end
end
