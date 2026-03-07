class Hiiro
  module Matchable
    # Find a single item by prefix match from a collection.
    # Returns the resolved match (exact or single) or first match if ambiguous.
    #
    # @param collection [Array] items to search
    # @param query [String] prefix to match
    # @param key [Symbol] method to call on items for comparison (default :name)
    # @return [Object, nil] matched item or nil
    def find_by_prefix(collection, query, key: :name)
      return nil if query.nil? || collection.empty?
      result = Matcher.new(collection, key).by_prefix(query)
      match = result.resolved || result.first
      match&.item
    end

    # Find all items matching a prefix from a collection.
    #
    # @param collection [Array] items to search
    # @param query [String] prefix to match
    # @param key [Symbol] method to call on items for comparison (default :name)
    # @return [Matcher::Result] match result with all matches
    def find_all_by_prefix(collection, query, key: :name)
      return Matcher::Result.empty if query.nil? || collection.empty?
      Matcher.new(collection, key).by_prefix(query)
    end
  end
end
