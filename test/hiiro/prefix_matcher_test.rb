require "test_helper"

class PrefixMatcherTest < Minitest::Test
  def test_find_with_exact_match
    items = %w[apple apricot banana]
    result = Hiiro::PrefixMatcher.find(items, "apple")

    assert_equal "apple", result
  end

  def test_find_with_prefix
    items = %w[apple apricot banana]
    result = Hiiro::PrefixMatcher.find(items, "ap")

    assert_equal "apple", result
  end

  def test_find_all_with_prefix
    items = %w[apple apricot banana]
    result = Hiiro::PrefixMatcher.find_all(items, "ap")

    assert_equal %w[apple apricot], result
  end

  def test_find_with_no_match
    items = %w[apple apricot banana]
    result = Hiiro::PrefixMatcher.find(items, "xyz")

    assert_nil result
  end

  def test_resolve_returns_exact_match_when_ambiguous
    items = %w[test testing tested]
    result = Hiiro::PrefixMatcher.resolve(items, "test")

    assert_equal "test", result
  end

  def test_resolve_returns_nil_when_ambiguous_no_exact
    items = %w[testing tested]
    result = Hiiro::PrefixMatcher.resolve(items, "test")

    assert_nil result
  end

  def test_resolve_returns_single_match
    items = %w[apple banana cherry]
    result = Hiiro::PrefixMatcher.resolve(items, "ban")

    assert_equal "banana", result
  end

  def test_find_with_key
    items = [
      OpenStruct.new(name: "alice", age: 30),
      OpenStruct.new(name: "bob", age: 25),
      OpenStruct.new(name: "charlie", age: 35),
    ]
    result = Hiiro::PrefixMatcher.find(items, "al", key: :name)

    assert_equal "alice", result.name
  end

  def test_find_with_block
    items = [
      { name: "alice", age: 30 },
      { name: "bob", age: 25 },
      { name: "charlie", age: 35 },
    ]
    result = Hiiro::PrefixMatcher.find(items, "bo") { |item| item[:name] }

    assert_equal({ name: "bob", age: 25 }, result)
  end

  def test_find_path_with_simple_path
    items = %w[src/main.rb src/lib.rb test/main_test.rb]
    result = Hiiro::PrefixMatcher.find_path(items, "src/main")

    assert_equal "src/main.rb", result
  end

  def test_find_path_with_abbreviated_segments
    items = %w[src/controllers/main.rb src/models/user.rb]
    result = Hiiro::PrefixMatcher.find_path(items, "src/c/m")

    assert_equal "src/controllers/main.rb", result
  end

  def test_find_all_paths
    items = %w[src/main.rb src/models/main.rb test/main_test.rb]
    result = Hiiro::PrefixMatcher.find_all_paths(items, "s/m")

    assert_includes result, "src/main.rb"
    assert_includes result, "src/models/main.rb"
  end

  def test_resolve_path_with_exact_match
    items = %w[main main/sub main/other]
    result = Hiiro::PrefixMatcher.resolve_path(items, "main")

    assert_equal "main", result
  end

  def test_resolve_path_single_match
    items = %w[src/main.rb test/main.rb]
    result = Hiiro::PrefixMatcher.resolve_path(items, "src/m")

    assert_equal "src/main.rb", result
  end
end

class PrefixMatcherItemTest < Minitest::Test
  def test_item_attributes
    item = Hiiro::PrefixMatcher::Item.new(
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

class PrefixMatcherResultTest < Minitest::Test
  def setup
    @matcher = Hiiro::PrefixMatcher.new(%w[apple apricot banana])
  end

  def test_result_matches
    items = @matcher.items.map { |extracted|
      Hiiro::PrefixMatcher::Item.new(item: extracted, extracted_item: extracted)
    }
    result = Hiiro::PrefixMatcher::Result.new(
      matcher: @matcher,
      all_items: items,
      prefix: "ap"
    )

    assert_equal 2, result.count
    assert result.match?
    assert result.ambiguous?
  end

  def test_result_one_match
    items = @matcher.items.map { |extracted|
      Hiiro::PrefixMatcher::Item.new(item: extracted, extracted_item: extracted)
    }
    result = Hiiro::PrefixMatcher::Result.new(
      matcher: @matcher,
      all_items: items,
      prefix: "ban"
    )

    assert_equal 1, result.count
    assert result.one?
    refute result.ambiguous?
    assert_equal "banana", result.match.extracted_item
  end

  def test_result_exact_match
    items = @matcher.items.map { |extracted|
      Hiiro::PrefixMatcher::Item.new(item: extracted, extracted_item: extracted)
    }
    result = Hiiro::PrefixMatcher::Result.new(
      matcher: @matcher,
      all_items: items,
      prefix: "apple"
    )

    assert result.exact?
    assert_equal "apple", result.exact_match.extracted_item
  end
end
