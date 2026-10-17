require 'test_helper'
require 'json'
require_relative '../support/cli_sandbox'

# `h hub` builds a symlink hub from an explicit catalog. Every test runs the
# real bin against a throwaway HOME, root and source tree.
class HubTest < Minitest::Test
  include CliSandbox

  def setup
    setup_sandbox
    @hub = File.join(@home, 'hub')
    @src = File.join(@home, 'src')
    @notes = File.join(@src, 'notes')
    @zsh = File.join(@src, 'zsh')
    FileUtils.mkdir_p([@notes, @zsh])
    File.write(File.join(@notes, 'a.txt'), 'alpha')
    File.write(File.join(@zsh, 'zshrc'), 'secret-ish')
    @catalog_path = File.join(@home, 'catalog.json')
  end

  def teardown = teardown_sandbox

  def catalog(links: nil, directories: nil)
    {
      'version' => 1, 'description' => 'test hub',
      'directories' => directories || { 'docs' => 'Documents', 'config' => 'Config', 'config/shell' => 'Shells' },
      'links' => links || [
        { 'name' => 'docs/notes', 'target' => @notes, 'description' => 'Notes' },
        { 'name' => 'config/shell/zsh', 'target' => @zsh, 'description' => 'Zsh' }
      ]
    }
  end

  def write_catalog(data = catalog)
    File.write(@catalog_path, JSON.generate(data))
    @catalog_path
  end

  def hub(*args, **opts) = run_bin('h-hub', *args, env: { 'H_HUB_ROOT' => @hub }, **opts)

  # Every path under dir with its type and contents, never following links.
  def snapshot(dir)
    Dir.glob(File.join(dir, '**', '*'), File::FNM_DOTMATCH).reject { |p| p.end_with?('/.', '/..') }.sort.to_h do |path|
      value = if File.symlink?(path) then [:link, File.readlink(path)]
              elsif File.directory?(path) then [:dir]
              else [:file, File.binread(path)]
              end
      [path, value]
    end
  end

  def test_init_creates_declared_links_and_repeat_is_safe_and_leaves_sources_alone
    sources = snapshot(@src)
    out, err, code = hub('init', write_catalog)
    assert_equal 0, code, out + err
    assert_equal sources, snapshot(@src)
    assert_equal @notes, File.readlink(File.join(@hub, 'docs', 'notes'))
    assert_equal @zsh, File.readlink(File.join(@hub, 'config', 'shell', 'zsh'))
    assert File.exist?(File.join(@hub, '.hub.json'))
    assert_equal '700', format('%o', File.stat(@hub).mode & 0o777)

    before = snapshot(@hub)
    refute_empty before

    # a second init, with a different catalog argument, must not overwrite the stored one
    other = File.join(@home, 'other.json')
    File.write(other, JSON.generate(catalog(links: [], directories: {})))
    _, err, code = hub('init', other)
    assert_equal 0, code, err
    assert_equal before, snapshot(@hub)
    _, err, code = hub('sync')
    assert_equal 0, code, err
    assert_equal before, snapshot(@hub)
    assert_equal sources, snapshot(@src)
  end

  def test_init_refuses_populated_unrelated_root
    FileUtils.mkdir_p(@hub)
    File.write(File.join(@hub, 'mine.txt'), 'keep')
    _, _, code = hub('init', write_catalog)
    refute_equal 0, code
    assert_equal ['mine.txt'], Dir.children(@hub)
    assert_equal 'keep', File.read(File.join(@hub, 'mine.txt'))
  end

  def test_conflicting_file_and_wrong_link_are_preserved
    hub('init', write_catalog)
    notes_link = File.join(@hub, 'docs', 'notes')
    zsh_link = File.join(@hub, 'config', 'shell', 'zsh')
    File.delete(notes_link)
    File.write(notes_link, 'user data')
    other = File.join(@home, 'elsewhere')
    FileUtils.mkdir_p(other)
    File.delete(zsh_link)
    File.symlink(other, zsh_link)

    _, _, code = hub('sync')
    refute_equal 0, code
    assert_equal 'user data', File.read(notes_link)
    refute File.symlink?(notes_link)
    assert_equal other, File.readlink(zsh_link)
    _, _, code = hub('doctor')
    refute_equal 0, code
  end

  def test_missing_source_is_reported_and_skipped_but_others_link
    FileUtils.rm_rf(@zsh)
    out, err, code = hub('init', write_catalog)
    refute_equal 0, code
    assert_includes out + err, 'zsh'
    assert_equal @notes, File.readlink(File.join(@hub, 'docs', 'notes'))
    refute File.exist?(File.join(@hub, 'config', 'shell', 'zsh')) || File.symlink?(File.join(@hub, 'config', 'shell', 'zsh'))
    _, _, code = hub('doctor')
    refute_equal 0, code

    FileUtils.mkdir_p(@zsh)
    assert_equal 0, hub('sync')[2]
    assert_equal 0, hub('doctor')[2]
  end

  def test_doctor_is_read_only
    hub('init', write_catalog)
    link = File.join(@hub, 'docs', 'notes')
    File.delete(link)
    before = snapshot(@hub)
    _, _, code = hub('doctor')
    refute_equal 0, code
    assert_equal before, snapshot(@hub)
  end

  def test_unsafe_logical_names_are_rejected_without_writing_outside_root
    outside = File.join(@home, 'outside')
    FileUtils.mkdir_p(outside)
    bad_names = ['../escape', '/abs/escape', 'docs/../../escape', '.hub.json', 'README.md',
                 'readme.md', '.HUB.JSON']
    bad_names.each do |name|
      data = catalog(links: [{ 'name' => name, 'target' => @notes, 'description' => 'x' }], directories: { 'docs' => 'D' })
      _, _, code = hub('init', write_catalog(data))
      refute_equal 0, code, name
      refute File.exist?(@hub) || File.symlink?(@hub), "#{name}: hub created"
      assert_empty Dir.children(outside), name
      refute File.exist?(File.join(@home, 'escape')), name
      refute File.exist?('/abs/escape'), name
      FileUtils.rm_rf(@hub)
    end
  end

  def test_symlinked_parent_directory_is_never_traversed
    hub('init', write_catalog)
    outside = File.join(@home, 'outside')
    FileUtils.mkdir_p(outside)
    FileUtils.rm_rf(File.join(@hub, 'docs'))
    File.symlink(outside, File.join(@hub, 'docs'))
    catalog_bytes = File.binread(File.join(@hub, '.hub.json'))

    _, _, code = hub('sync')
    refute_equal 0, code
    assert_empty Dir.children(outside)
    assert File.symlink?(File.join(@hub, 'docs'))
    _, _, code = hub('add', 'docs/extra', @zsh, 'Extra')
    refute_equal 0, code
    assert_empty Dir.children(outside)
    assert_equal catalog_bytes, File.binread(File.join(@hub, '.hub.json'))
  end

  def test_failed_add_over_user_file_or_wrong_link_leaves_catalog_and_destination_unchanged
    hub('init', write_catalog)
    path = File.join(@hub, '.hub.json')
    extra = File.join(@home, 'extra')
    other = File.join(@home, 'elsewhere')
    FileUtils.mkdir_p([extra, other])
    dest = File.join(@hub, 'docs', 'extra')
    before = File.binread(path)

    File.write(dest, 'user data')
    _, _, code = hub('add', 'docs/extra', extra, 'Extra')
    refute_equal 0, code
    assert_equal before, File.binread(path)
    refute File.symlink?(dest)
    assert_equal 'user data', File.binread(dest)

    File.delete(dest)
    File.symlink(other, dest)
    _, _, code = hub('add', 'docs/extra', extra, 'Extra')
    refute_equal 0, code
    assert_equal before, File.binread(path)
    assert_equal other, File.readlink(dest)
  end

  def test_symlinked_root_is_not_traversed
    outside = File.join(@home, 'outside')
    FileUtils.mkdir_p(outside)
    File.symlink(outside, @hub)
    _, _, code = hub('init', write_catalog)
    refute_equal 0, code
    assert_empty Dir.children(outside)
  end

  def test_targets_inside_the_hub_are_rejected
    hub('init', write_catalog)
    inner = File.join(@hub, 'docs')
    _, _, code = hub('add', 'loop', inner, 'Loop')
    refute_equal 0, code
    refute File.exist?(File.join(@hub, 'loop')) || File.symlink?(File.join(@hub, 'loop'))
  end

  def test_leaf_link_cannot_be_ancestor_of_another_entry
    data = catalog(links: [
      { 'name' => 'docs/notes', 'target' => @notes, 'description' => 'N' },
      { 'name' => 'docs/notes/deeper', 'target' => @zsh, 'description' => 'Z' }
    ])
    _, _, code = hub('init', write_catalog(data))
    refute_equal 0, code
    assert_empty Dir.children(@notes).reject { |f| f == 'a.txt' }
    assert_empty Dir.children(@zsh).reject { |f| f == 'zshrc' }
  end

  def test_find_matches_filenames_only_including_spaces_and_skips_noise_and_cycles
    sub = File.join(@notes, 'sub dir')
    FileUtils.mkdir_p([sub, File.join(@notes, 'node_modules'), File.join(@notes, '.git')])
    File.write(File.join(sub, 'Report One.txt'), 'x')
    File.write(File.join(@notes, 'top report.md'), 'x')
    File.write(File.join(@notes, 'node_modules', 'report.js'), 'x')
    File.write(File.join(@notes, '.git', 'report'), 'x')
    File.write(File.join(@notes, 'body.txt'), 'this mentions report in contents only')
    File.symlink(@notes, File.join(sub, 'cycle'))
    File.symlink(@zsh, File.join(@notes, 'interior'))
    File.write(File.join(@zsh, 'report-in-other-link.txt'), 'x')
    hub('init', write_catalog)

    out, err, code = hub('find', 'docs/notes', 'REPORT')
    assert_equal 0, code, err
    expected = [File.join(@hub, 'docs', 'notes', 'sub dir', 'Report One.txt'),
                File.join(@hub, 'docs', 'notes', 'top report.md')]
    assert_equal expected, out.lines.map(&:chomp).sort

    out, = hub('find', 'config', 'report')
    assert_equal [File.join(@hub, 'config', 'shell', 'zsh', 'report-in-other-link.txt')], out.lines.map(&:chomp)

    out, = hub('find', 'docs/notes', 'report', '--limit', '1')
    assert_equal 1, out.lines.size
  end

  def test_add_persists_in_catalog_path_and_survives_sync
    hub('init', write_catalog)
    extra = File.join(@home, 'extra')
    FileUtils.mkdir_p(extra)
    out, err, code = hub('add', 'docs/extra', extra, 'Extra things')
    assert_equal 0, code, out + err
    link = File.join(@hub, 'docs', 'extra')
    assert_equal extra, File.readlink(link)

    stored = JSON.parse(File.read(File.join(@hub, '.hub.json')))
    entry = stored['links'].find { |l| l['name'] == 'docs/extra' }
    assert_equal 'Extra things', entry['description']
    assert_equal 3, stored['links'].size

    assert_equal [link, 0], [hub('path', 'docs/extra')[0].chomp, 0]
    assert_equal @hub, hub('path')[0].chomp
    assert_equal File.join(@hub, 'docs'), hub('path', 'docs')[0].chomp
    assert_equal 0, hub('sync')[2]
    assert_equal extra, File.readlink(link)
    assert_equal 0, hub('doctor')[2]
  end

  def test_add_refuses_duplicates_missing_targets_and_blank_descriptions_without_changing_catalog
    hub('init', write_catalog)
    path = File.join(@hub, '.hub.json')
    before = File.read(path)
    snap = snapshot(@hub)
    extra = File.join(@home, 'extra')
    FileUtils.mkdir_p(extra)
    [['docs/notes', extra, 'dup'], ['docs/new', File.join(@home, 'nope'), 'missing target'],
     ['docs/new', extra, ''], ['docs', extra, 'group name']].each do |args|
      _, _, code = hub('add', *args)
      refute_equal 0, code, args.inspect
      assert_equal before, File.read(path), args.inspect
      assert_equal snap, snapshot(@hub), args.inspect
    end
  end
end
