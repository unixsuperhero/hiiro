require "test_helper"
require_relative '../../plugins/pins'

class LinkTest < Minitest::Test
  def setup
    clear
    @harness = Hiiro::TestHarness.load_bin('bin/h-link')
    @manager = LinkManager.new
  end

  def teardown
    clear
  end

  def clear
    Hiiro::Tag.where(taggable_type: 'RegistryEntry').delete
    Hiiro::RegistryEntry.where(resource_type: 'link').delete
  end

  def link(url, description: 'original', shorthand: 'ex', created_at: '2026-01-01T00:00:00Z', tags: ['legacy'])
    @manager.create(url: url, description: description, shorthand: shorthand, created_at: created_at, tags: tags)
  end

  def rows = Hiiro::RegistryEntry.where(resource_type: 'link').order(:id).all
  def entry(link) = Hiiro::RegistryEntry[link.id]

  def baseline(*links)
    links.to_h { |link| [link.id, { values: entry(link).values.dup, tags: Hiiro::Tag.for(entry(link)).order(:id).map { |tag| tag.values.dup } }] }
  end

  def test_add_list_and_remove_preserve_another_link_and_its_tags
    other = link('https://other', shorthand: 'other', tags: ['keep'])
    capture_io { @harness.run_subcmd(:add, 'https://new', 'new description', '--shorthand', 'new', '--tag', 'owned') }
    added = Hiiro::Table.named('link').find('new')
    assert_equal ['https://new', 'new description', 'new', ['owned']], [added.value, added.description, added.short_name, added.tags]
    output, = capture_io { @harness.run_subcmd(:ls) }
    assert_includes output, 'https://new - new description'
    assert_includes output, 'https://other - original'
    capture_io { @harness.run_subcmd(:rm, 'new') }
    assert_equal [[other.id, 'https://other', ['keep']]], rows.map { |record| [record.id, record.value, record.tags] }
    assert_equal ['keep'], Hiiro::Tag.where(taggable_type: 'RegistryEntry').map(&:name)
  end

  def test_display_string_matches_the_numbered_ls_line
    row = Hiiro::RegistryEntry.new(resource_type: "link", name: "jf", short_name: "jf", value: "http://x", description: "jellyfin")

    assert_equal "2. [jf] http://x - jellyfin", LinkPresenter.new(row).display_string(1)
  end

  def test_url_edit_preserves_stable_id_tags_and_concurrent_description
    original = link('https://old', tags: ['keep'])
    before = baseline(original)
    entry(original).update(description: 'concurrent')
    inserted = link('https://inserted', shorthand: 'new')
    @manager.apply_edit([original.to_h.merge('url' => 'https://edited')], baseline: before)
    actual = entry(original)
    assert_equal ['https://edited', 'concurrent', 'ex', ['keep'], '2026-01-01T00:00:00Z'], [actual.value, actual.description, actual.short_name, actual.tags, actual.created_at]
    assert_equal [original.id, inserted.id], rows.map(&:id)
  end

  def test_bulk_editor_deletes_only_selected_ids_and_allocates_new_ids
    first = link('https://first', shorthand: nil, tags: ['owned'])
    second = link('https://second', shorthand: 'second')
    before = baseline(first, second)
    inserted = link('https://concurrent', shorthand: 'concurrent')
    @manager.apply_edit([second.to_h.merge('description' => 'edited'), { 'url' => 'https://new' }], baseline: before)
    assert_equal [[second.id, 'https://second', 'edited'], [inserted.id, 'https://concurrent', 'original'], [inserted.id + 1, 'https://new', '']], rows.map { |record| [record.id, record.value, record.description] }
    assert_empty Hiiro::Tag.where(taggable_type: 'RegistryEntry', taggable_id: first.id.to_s).all
  end

  def test_conflict_rolls_back_other_edits_and_deletions
    first = link('https://first', shorthand: nil)
    second = link('https://second', shorthand: 'second')
    before = baseline(first, second)
    entry(second).update(description: 'other writer')
    error = assert_raises(Hiiro::Error) { @manager.apply_edit([second.to_h.merge('description' => 'editor')], baseline: before) }
    assert_includes error.message, 'changed concurrently'
    assert_equal [[first.id, 'original'], [second.id, 'other writer']], rows.map { |record| [record.id, record.description] }
  end

  def test_changed_tags_prevent_stale_deletion
    first = link('https://first')
    before = baseline(first)
    entry(first).tag('concurrent')
    assert_raises(Hiiro::Error) { @manager.apply_edit([], baseline: before) }
    assert_equal ['https://first', ['concurrent', 'legacy']], [entry(first).value, entry(first).tags]
  end

  def test_omitted_fields_are_preserved_and_explicit_null_clears
    original = link('https://old')
    @manager.apply_edit([{ 'id' => original.id, 'shorthand' => nil }], baseline: baseline(original))
    assert_equal ['https://old', 'original', nil], entry(original).values.values_at(:value, :description, :short_name)
  end

  def test_deleted_edited_row_is_not_resurrected
    original = link('https://old')
    before = baseline(original)
    @manager.delete(original)
    survivor = link('https://survivor', shorthand: nil)
    assert_raises(Hiiro::Error) { @manager.apply_edit([original.to_h.merge('url' => 'https://edited')], baseline: before) }
    assert_equal [[survivor.id, 'https://survivor']], rows.map { |record| [record.id, record.value] }
  end

  def test_unknown_duplicate_and_malformed_ids_abort_without_changes
    original = link('https://old')
    before = baseline(original)
    [[{ 'id' => original.id + 999, 'url' => 'https://bad' }], [original.to_h, original.to_h], [original.to_h.merge('id' => original.id.to_s)]].each do |rows_in|
      assert_raises(Hiiro::Error) { @manager.apply_edit(rows_in, baseline: before) }
      assert_equal [[original.id, 'https://old']], rows.map { |record| [record.id, record.value] }
    end
  end

  def test_blank_unchanged_and_failed_editor_output_never_writes
    original = link('https://old')
    editor = Object.new
    ['', nil].each do |contents|
      editor.define_singleton_method(:edit_files) { |path| File.write(path, contents) if contents; true }
      assert_nil @manager.edit_links([original], hiiro: editor)
      assert_equal ['https://old', ['legacy']], [entry(original).value, entry(original).tags]
    end
    editor.define_singleton_method(:edit_files) { |path| File.write(path, [].to_yaml); false }
    assert_raises(Hiiro::Error) { @manager.edit_links([original], hiiro: editor) }
    assert_equal [[original.id, 'https://old']], rows.map { |record| [record.id, record.value] }
  end

  def test_path_names_the_database_and_table
    output, = capture_io { @harness.run_subcmd(:path) }
    assert_equal "#{Hiiro::DB::DB_FILE} (table link)", output
  end
end
