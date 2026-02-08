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
      items(key, &block).find { |item| matches?(item, prefix) }
    end

    def find_all(prefix, key = nil, &block)
      items(key, &block).select { |item| matches?(item, prefix) }
    end

    def resolve(prefix, key = nil, &block)
      exact = items(key, &block).find { |item| item == prefix }
      return exact if exact

      matches = items(key, &block).select { |item| matches?(item, prefix) }
      matches.one? ? matches.first : nil
    end

    def find_path(prefix, key = nil, &block)
      matching_paths(prefix, key, &block).first
    end

    def find_all_paths(prefix, key = nil, &block)
      matching_paths(prefix, key, &block)
    end

    def resolve_path(prefix, key = nil, &block)
      matches = matching_paths(prefix, key, &block)
      return nil if matches.empty?
      return matches.first if matches.one?
      matches.find { |path| path == prefix }
    end

    private

    def matching_paths(prefix, key = nil, &block)
      prefixes = prefix.to_s.split('/')

      paths = items(key, &block).map { |item| item.to_s.split('/') }

      prefixes.each_with_index do |seg, i|
        paths = paths.select { |path| path[i]&.start_with?(seg) }
      end

      paths.map { |p| p.join('/') }
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
