require "test_helper"

class MatcherTest < Minitest::Test
  def test_find_with_exact_match
    items = %w[apple apricot banana]
    result = Hiiro::Matcher.find(items, "apple")

    assert_equal "apple", result
  end

  def test_find_with_prefix
    items = %w[apple apricot banana]
    result = Hiiro::Matcher.find(items, "ap")

    assert_equal "apple", result
  end

  def test_find_all_with_prefix
    items = %w[apple apricot banana]
    result = Hiiro::Matcher.find_all(items, "ap")

    assert_equal %w[apple apricot], result
  end

  def test_find_with_no_match
    items = %w[apple apricot banana]
    result = Hiiro::Matcher.find(items, "xyz")

    assert_nil result
  end

  def test_resolve_returns_exact_match_when_ambiguous
    items = %w[test testing tested]
    result = Hiiro::Matcher.resolve(items, "test")

    assert_equal "test", result
  end

  def test_resolve_returns_nil_when_ambiguous_no_exact
    items = %w[testing tested]
    result = Hiiro::Matcher.resolve(items, "test")

    assert_nil result
  end

  def test_resolve_returns_single_match
    items = %w[apple banana cherry]
    result = Hiiro::Matcher.resolve(items, "ban")

    assert_equal "banana", result
  end

  def test_find_with_key
    items = [
      OpenStruct.new(name: "alice", age: 30),
      OpenStruct.new(name: "bob", age: 25),
      OpenStruct.new(name: "charlie", age: 35),
    ]
    result = Hiiro::Matcher.find(items, "al", key: :name)

    assert_equal "alice", result.name
  end

  def test_find_with_block
    items = [
      { name: "alice", age: 30 },
      { name: "bob", age: 25 },
      { name: "charlie", age: 35 },
    ]
    result = Hiiro::Matcher.find(items, "bo") { |item| item[:name] }

    assert_equal({ name: "bob", age: 25 }, result)
  end

  def test_find_path_with_simple_path
    items = %w[src/main.rb src/lib.rb test/main_test.rb]
    result = Hiiro::Matcher.find_path(items, "src/main")

    assert_equal "src/main.rb", result
  end

  def test_find_path_with_abbreviated_segments
    items = %w[src/controllers/main.rb src/models/user.rb]
    result = Hiiro::Matcher.find_path(items, "src/c/m")

    assert_equal "src/controllers/main.rb", result
  end

  def test_find_all_paths
    items = %w[src/main.rb src/models/main.rb test/main_test.rb]
    result = Hiiro::Matcher.find_all_paths(items, "s/m")

    assert_includes result, "src/main.rb"
    assert_includes result, "src/models/main.rb"
  end

  def test_resolve_path_with_exact_match
    items = %w[main main/sub main/other]
    result = Hiiro::Matcher.resolve_path(items, "main")

    assert_equal "main", result
  end

  def test_resolve_path_single_match
    items = %w[src/main.rb test/main.rb]
    result = Hiiro::Matcher.resolve_path(items, "src/m")

    assert_equal "src/main.rb", result
  end

  # New substring matching tests
  def test_by_substring_finds_match_in_middle
    items = %w[apple pineapple banana]
    matcher = Hiiro::Matcher.new(items)
    result = matcher.by_substring("apple")

    assert_equal 2, result.count
    assert_includes result.matches.map(&:item), "apple"
    assert_includes result.matches.map(&:item), "pineapple"
  end

  def test_by_substring_finds_match_at_end
    items = %w[apple application]
    matcher = Hiiro::Matcher.new(items)
    result = matcher.by_substring("tion")

    assert_equal 1, result.count
    assert_equal "application", result.first.item
  end

  def test_by_substring_class_method
    items = %w[hello world hello_world]
    result = Hiiro::Matcher.by_substring(items, "world")

    assert_equal 2, result.count
    assert_includes result.matches.map(&:item), "world"
    assert_includes result.matches.map(&:item), "hello_world"
  end

  def test_by_substring_with_key
    items = [
      OpenStruct.new(name: "alice_smith"),
      OpenStruct.new(name: "bob_jones"),
      OpenStruct.new(name: "charlie_smith"),
    ]
    matcher = Hiiro::Matcher.new(items, :name)
    result = matcher.by_substring("smith")

    assert_equal 2, result.count
    assert_equal "alice_smith", result.matches[0].item.name
    assert_equal "charlie_smith", result.matches[1].item.name
  end

  def test_by_prefix_explicit_method
    items = %w[apple apricot banana]
    result = Hiiro::Matcher.by_prefix(items, "ap")

    assert_equal 2, result.count
    assert_includes result.matches.map(&:item), "apple"
    assert_includes result.matches.map(&:item), "apricot"
  end

  def test_backward_compatibility_prefix_matcher_alias
    # Ensure old code still works
    items = %w[apple apricot banana]
    result = Hiiro::PrefixMatcher.find(items, "ap")

    assert_equal "apple", result
  end
end

class MatcherItemTest < Minitest::Test
  def test_item_attributes
    item = Hiiro::Matcher::Item.new(
      item: "original",
      extracted_item: "extracted",
      key: :name,
      block: nil
    )

    assert_equal "original", item.item
    assert_equal "extracted", item.extracted_item
    assert_equal :name, item.key
    assert_nil item.block
  end
end

class MatcherResultTest < Minitest::Test
  def setup
    @matcher = Hiiro::Matcher.new(%w[apple apricot banana])
  end

  def test_result_matches
    items = @matcher.all_items.map { |i| i }
    result = Hiiro::Matcher::Result.new(
      matcher: @matcher,
      all_items: items,
      pattern: "ap"
    )

    assert_equal 2, result.count
    assert result.match?
    assert result.ambiguous?
  end

  def test_result_one_match
    items = @matcher.all_items.map { |i| i }
    result = Hiiro::Matcher::Result.new(
      matcher: @matcher,
      all_items: items,
      pattern: "ban"
    )

    assert_equal 1, result.count
    assert result.one?
    refute result.ambiguous?
    assert_equal "banana", result.match.extracted_item
  end

  def test_result_exact_match
    items = @matcher.all_items.map { |i| i }
    result = Hiiro::Matcher::Result.new(
      matcher: @matcher,
      all_items: items,
      pattern: "apple"
    )

    assert result.exact?
    assert_equal "apple", result.exact_match.extracted_item
  end

  def test_result_prefix_alias
    result = Hiiro::Matcher::Result.new(
      matcher: @matcher,
      all_items: @matcher.all_items,
      pattern: "test"
    )

    assert_equal "test", result.prefix
    assert_equal "test", result.pattern
  end

  def test_substring_result
    items = @matcher.all_items.map { |i| i }
    result = Hiiro::Matcher::Result.new(
      matcher: @matcher,
      all_items: items,
      pattern: "le",
      match_type: :substring
    )

    assert_equal 1, result.count
    assert_equal "apple", result.first.extracted_item
  end
end
