require "test_helper"

class TagsTest < Minitest::Test
  def setup
    Hiiro::Tag.dataset.delete
    @objects = []
  end

  def teardown
    Hiiro::Tag.dataset.delete
    @objects.reverse_each(&:destroy)
  end

  def persist(model, **fields)
    model.create(**fields).tap { |row| @objects << row }
  end

  def test_name_namespaces_and_model_ids_resolve_the_exact_relations
    branch = persist(Hiiro::Branch, name: "0042")
    task = persist(Hiiro::TaskRecord, name: "0042")
    link = persist(Hiiro::Link, url: "https://tag-test.example")
    entry = persist(Hiiro::RegistryEntry, resource_type: "tag-test", name: "saved", task_id: task.id)

    Hiiro::Tags.new(:branch).add("0042", "branch-name")
    Hiiro::Tags.new(:task).add("0042", "task-name")
    Hiiro::Tag.tag!(task, "task-record")
    Hiiro::Tag.tag!(link, "link-record")
    entry.tag("entry-record")

    assert_equal [["Branch", "0042"], ["Task", "0042"], ["TaskRecord", task.id.to_s],
      ["Link", link.id.to_s], ["RegistryEntry", entry.id.to_s]],
      Hiiro::Tag.order(:id).select_map([:taggable_type, :taggable_id])
    assert_equal [branch, task, task, link, entry], Hiiro::Tag.order(:id).map(&:taggable)
    assert_equal ["task-name"], Hiiro::Tags.new(:task).get("0042")
    assert_equal ["task-record"], Hiiro::Tag.for(task).select_map(:name)
    assert_equal ["entry-record"], Hiiro::RegistryEntry[entry.id].tags
    assert_equal task.id, Hiiro::RegistryEntry[entry.id].task_id
  end

  def test_stale_namespace_readers_preserve_other_keys_namespaces_and_row_ids
    old = Hiiro::Tags.new(:branch)
    newer = Hiiro::Tags.new(:branch)
    old.add("alpha", "work", "review")
    initial = old.all
    retained_id = Hiiro::Tag.where(name: "work", taggable_type: "Branch", taggable_id: "alpha").get(:id)

    newer.add("alpha", "urgent")
    newer.add("beta", "other")
    Hiiro::Tags.new(:task).add("alpha", "task-tag")
    old.remove("alpha", "review")
    old.add("alpha", "work", "work")

    assert_equal({ "alpha" => %w[work review] }, initial)
    assert_equal({ "alpha" => %w[work urgent], "beta" => ["other"] }, old.all)
    assert_equal({ "alpha" => ["task-tag"] }, Hiiro::Tags.new(:task).all)
    assert_equal retained_id, Hiiro::Tag.where(name: "work", taggable_type: "Branch", taggable_id: "alpha").get(:id)

    old.remove("alpha")
    assert_equal({ "beta" => ["other"] }, newer.all)
    assert_equal({ "alpha" => ["task-tag"] }, Hiiro::Tags.new(:task).all)
  end

  def test_stale_object_mutation_preserves_other_objects_and_tag_ids
    link = persist(Hiiro::Link, url: "https://tag-test.example/first")
    other = persist(Hiiro::Link, url: "https://tag-test.example/second")
    stale = Hiiro::Link[link.id]
    Hiiro::Tag.tag!(stale, "work", "review")
    retained_id = Hiiro::Tag.for(link).where(name: "work").get(:id)
    Hiiro::Tag.tag!(link, "urgent")
    Hiiro::Tag.tag!(other, "review")

    Hiiro::Tag.untag!(stale, "review")
    Hiiro::Tag.tag!(stale, "work")

    assert_equal %w[urgent work], Hiiro::Link[link.id].tags.sort
    assert_equal ["review"], Hiiro::Link[other.id].tags
    assert_equal retained_id, Hiiro::Tag.for(link).where(name: "work").get(:id)
  end

  def test_multi_tag_assignment_rolls_back_on_a_database_rejection
    store = Hiiro::Tags.new(:branch)
    link = persist(Hiiro::Link, url: "https://tag-test.example/atomic")
    store.add("alpha", "kept")
    Hiiro::Tag.tag!(link, "kept")
    Hiiro::Tag.db.run("CREATE TEMP TRIGGER reject_tag BEFORE INSERT ON tags WHEN NEW.name = 'rejected' BEGIN SELECT RAISE(ABORT, 'rejected tag'); END")

    assert_raises(Sequel::DatabaseError) { store.add("alpha", "partial", "rejected") }
    assert_raises(Sequel::DatabaseError) { Hiiro::Tag.tag!(link, "partial", "rejected") }
    assert_equal ["kept"], store.get("alpha")
    assert_equal ["kept"], Hiiro::Link[link.id].tags
  ensure
    Hiiro::Tag.db.run("DROP TRIGGER IF EXISTS reject_tag")
  end

  def test_search_returns_distinct_names_and_resolves_only_the_requested_type
    first = persist(Hiiro::Link, url: "https://tag-test.example/search-one")
    second = persist(Hiiro::Link, url: "https://tag-test.example/search-two")
    Hiiro::Tag.tag!(first, "work", "urgent")
    Hiiro::Tag.tag!(second, "work")
    Hiiro::Tags.new(:branch).add("alpha", "branch-only")

    assert_equal %w[urgent work], Hiiro::Tag.search(type: "Link")
    assert_equal ["work"], Hiiro::Tag.search(["wor"], type: "Link")
    assert_equal [first, second], Hiiro::Tag.tagged_by_type("work", "Link")
    assert_equal %w[branch-only urgent work], Hiiro::Tag.tags_by_type
    assert_equal ["branch-only"], Hiiro::Tags.new(:branch).known_tags
  end
end
