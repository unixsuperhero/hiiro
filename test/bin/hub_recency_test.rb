require 'test_helper'
require 'json'
require 'time'
require_relative '../support/cli_sandbox'

# `h hub recent` / `h hub latest` over a throwaway HOME. Every timestamp is set
# with File.utime to a literal; nothing sleeps and nothing reads the real clock.
class HubRecencyTest < Minitest::Test
  include CliSandbox
  include CommitFixture

  def setup
    setup_sandbox
    @hub = File.join(@home, 'hub')
    @src = File.join(@home, 'src')
    @notes = File.join(@src, 'notes')
    @downloads = File.join(@src, 'downloads')
    @projects = File.join(@src, 'projects')
    FileUtils.mkdir_p([@notes, @downloads, @projects])
    @catalog_path = File.join(@home, 'catalog.json')
  end

  def teardown = teardown_sandbox

  # Day N of January 2026, noon UTC.
  def at(day) = Time.utc(2026, 1, day, 12)

  # Parses an ISO8601 timestamp that must be written in UTC ('Z').
  def utc_time(text)
    assert text.end_with?('Z'), text
    Time.iso8601(text)
  end

  def stamp(path, day)
    File.lutime(at(day), at(day), path)
  end

  def put(path, day, body = 'x')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    stamp(path, day)
    path
  end

  def init_hub(links = nil)
    links ||= [{ 'name' => 'docs/notes', 'target' => @notes, 'description' => 'Notes' },
               { 'name' => 'downloads', 'target' => @downloads, 'description' => 'Downloads' },
               { 'name' => 'projects', 'target' => @projects, 'description' => 'Projects' }]
    data = { 'version' => 1, 'description' => 'test hub', 'directories' => { 'docs' => 'Documents' }, 'links' => links }
    File.write(@catalog_path, JSON.generate(data))
    out, err, code = hub('init', @catalog_path)
    assert_equal 0, code, out + err
  end

  def hub(*args, **opts) = run_bin('h-hub', *args, env: { 'H_HUB_ROOT' => @hub }, **opts)

  def recent_json(*args)
    out, err, code = hub('recent', *args, '--json')
    assert_equal 0, code, err
    JSON.parse(out)
  end

  def hub_path(*parts) = File.join(@hub, *parts)

  # Every path under dir with type, contents and mtime, never following links.
  def snapshot(dir)
    Dir.glob(File.join(dir, '**', '*'), File::FNM_DOTMATCH).reject { |p| p.end_with?('/.', '/..') }.sort.to_h do |path|
      st = File.lstat(path)
      value = if st.symlink? then [:link, File.readlink(path), st.mtime.to_f]
              elsif st.directory? then [:dir, st.mtime.to_f]
              else [:file, File.binread(path), st.mtime.to_f]
              end
      [path, value]
    end
  end

  def git_project(name)
    repo = File.join(@projects, name)
    FileUtils.mkdir_p(File.join(repo, 'src'))
    git_in(repo, 'init', '-q', '-b', 'main')
    put(File.join(repo, '.gitignore'), 1, "build/\n")
    put(File.join(repo, 'src', 'main.rb'), 1, 'puts 1')
    git_in(repo, 'add', '.')
    git_in(repo, 'commit', '-q', '-m', 'init')
    repo
  end

  def test_nested_note_mtime_beats_directory_mtime_and_any_extension_counts
    put(File.join(@notes, 'old.md'), 1)
    put(File.join(@notes, 'deep', 'er', 'log.csv'), 5)
    put(File.join(@notes, 'mid.txt'), 3)
    [File.join(@notes, 'deep', 'er'), File.join(@notes, 'deep'), @notes].each { |d| stamp(d, 9) }
    init_hub

    rows = recent_json('docs/notes')
    assert_equal [hub_path('docs', 'notes', 'deep', 'er', 'log.csv'),
                  hub_path('docs', 'notes', 'mid.txt'),
                  hub_path('docs', 'notes', 'old.md')], rows.map { |r| r['path'] }
    assert_equal [at(5), at(3), at(1)], rows.map { |r| utc_time(r['timestamp']) }
    assert_equal ['modified'], rows.map { |r| r['basis'] }.uniq
    assert_equal %w[basis name path timestamp], rows.first.keys.sort
    assert rows.all? { |r| r['name'].is_a?(String) && !r['name'].empty? }
  end

  def test_limit_applies_after_scanning_everything
    %w[a b c d].each_with_index { |n, i| put(File.join(@notes, "#{n}.txt"), 10 - i * 2) }
    put(File.join(@notes, 'zz', 'newest.txt'), 20)
    init_hub

    assert_equal [hub_path('docs', 'notes', 'zz', 'newest.txt'), hub_path('docs', 'notes', 'a.txt')],
                 recent_json('docs/notes', '--limit', '2').map { |r| r['path'] }
    assert_equal 5, recent_json('docs/notes').size
  end

  def test_default_limit_is_twenty
    25.times { |i| put(File.join(@notes, format('n%02d.txt', i)), 1 + i % 28, 'x') }
    init_hub
    assert_equal 20, recent_json('docs/notes').size
  end

  def test_equal_timestamps_break_ties_by_path_deterministically
    %w[c.txt a.txt b.txt].each { |n| put(File.join(@notes, n), 4) }
    init_hub

    expected = %w[a.txt b.txt c.txt].map { |n| hub_path('docs', 'notes', n) }
    2.times { assert_equal expected, recent_json('docs/notes').map { |r| r['path'] } }
    assert_equal expected.first, hub('latest', 'docs/notes')[0].chomp
  end

  def test_noise_directories_and_files_are_skipped
    put(File.join(@notes, 'real.txt'), 2)
    %w[.git node_modules .cache .obsidian __pycache__ .venv venv dist build target .next vendor].each do |dir|
      put(File.join(@notes, dir, 'newer.txt'), 9)
    end
    %w[.DS_Store .localized].each { |f| put(File.join(@notes, f), 9) }
    init_hub

    assert_equal [hub_path('docs', 'notes', 'real.txt')], recent_json('docs/notes').map { |r| r['path'] }
  end

  def test_downloads_list_complete_direct_items_only
    put(File.join(@downloads, 'done.zip'), 2)
    put(File.join(@downloads, 'Folder X', 'inner', 'deep.txt'), 3)
    put(File.join(@downloads, 'inner-newer.txt'), 1)
    %w[a.part b.crdownload c.download d.partial e.tmp .hidden.txt].each { |n| put(File.join(@downloads, n), 9) }
    FileUtils.mkdir_p(File.join(@downloads, '.hidden-dir'))
    init_hub

    rows = recent_json('downloads')
    assert_equal %w[Folder\ X done.zip inner-newer.txt].sort, rows.map { |r| File.basename(r['path']) }.sort
    assert_equal rows.map { |r| r['path'] }, rows.map { |r| hub_path('downloads', File.basename(r['path'])) }
    refute rows.any? { |r| r['path'].include?('deep.txt') }

    # basis is the local creation time where macOS reports one, else mtime
    rows.each do |r|
      real = File.join(@downloads, File.basename(r['path']))
      born = begin
        File.lstat(real).birthtime
      rescue NotImplementedError
        nil
      end
      if r['basis'] == 'created'
        assert_equal born.utc.iso8601, Time.iso8601(r['timestamp']).utc.iso8601, r.inspect
      else
        assert_equal 'modified', r['basis']
        assert_nil born
        assert_equal File.lstat(real).mtime.utc.iso8601, Time.iso8601(r['timestamp']).utc.iso8601
      end
      assert r['timestamp'].end_with?('Z')
    end

    assert_equal 'created', rows.first['basis'] if File.lstat(File.join(@downloads, 'done.zip')).respond_to?(:birthtime) && RUBY_PLATFORM.include?('darwin')
  end

  def test_git_project_uses_newest_non_ignored_source_change
    repo = git_project('alpha')
    put(File.join(repo, 'src', 'main.rb'), 5, 'puts 2')      # uncommitted edit
    put(File.join(repo, 'src', 'fresh.rb'), 6)               # untracked
    put(File.join(repo, 'build', 'out.js'), 8)               # ignored output
    stamp(File.join(repo, 'build'), 8)
    [File.join(repo, 'src'), repo].each { |d| stamp(d, 1) }
    stamp(File.join(repo, '.git'), 9)
    init_hub

    rows = recent_json('projects')
    assert_equal [hub_path('projects', 'alpha')], rows.map { |r| r['path'] }
    assert_equal at(6), utc_time(rows.first['timestamp'])
    assert_equal 'modified', rows.first['basis']
  end

  def test_non_git_project_counts_directory_changes_and_ignores_noise_and_outside_symlinks
    plain = File.join(@projects, 'beta')
    put(File.join(plain, 'src', 'x.rb'), 3)
    put(File.join(plain, 'node_modules', 'big.js'), 9)
    outside = put(File.join(@src, 'outside.txt'), 9)
    File.symlink(outside, File.join(plain, 'outside-link'))
    stamp(File.join(plain, 'outside-link'), 2)
    FileUtils.mkdir_p(File.join(plain, 'empty'))
    stamp(File.join(plain, 'empty'), 7)             # an empty directory still counts
    stamp(File.join(plain, 'src'), 4)
    stamp(plain, 5)
    init_hub

    rows = recent_json('projects')
    assert_equal [hub_path('projects', 'beta')], rows.map { |r| r['path'] }
    assert_equal at(7), utc_time(rows.first['timestamp'])
  end

  def test_git_project_does_not_follow_intermediate_symlink_to_outside_newer_file
    repo = git_project('alpha')
    put(File.join(repo, 'nested', 'file.rb'), 1)
    git_in(repo, 'add', '.')
    git_in(repo, 'commit', '-q', '-m', 'nested')
    outside = File.join(@src, 'outside-tree')
    put(File.join(outside, 'file.rb'), 20)
    FileUtils.rm_rf(File.join(repo, 'nested'))
    File.symlink(outside, File.join(repo, 'nested'))
    [File.join(repo, 'nested'), File.join(repo, 'src', 'main.rb'), File.join(repo, 'src'), repo].each { |p| stamp(p, 2) }
    init_hub

    assert_equal at(2), utc_time(recent_json('projects').first['timestamp'])
  end

  def test_git_project_counts_containing_directory_for_deletion_and_addition
    repo = git_project('alpha')
    put(File.join(repo, 'src', 'gone.rb'), 1)
    git_in(repo, 'add', '.')
    git_in(repo, 'commit', '-q', '-m', 'gone')
    FileUtils.rm(File.join(repo, 'src', 'gone.rb'))
    put(File.join(repo, 'src', 'main.rb'), 1)
    stamp(File.join(repo, 'src'), 7)       # the deletion changed this directory
    stamp(repo, 1)
    init_hub

    assert_equal at(7), utc_time(recent_json('projects').first['timestamp'])

    FileUtils.rm_rf(File.join(repo, 'src'))  # whole parent gone: nearest surviving parent is the root
    stamp(repo, 9)
    assert_equal at(9), utc_time(recent_json('projects').first['timestamp'])
  end

  def test_projects_are_one_row_each_newest_first
    a = git_project('alpha')
    put(File.join(a, 'src', 'a.rb'), 4)
    [File.join(a, 'src'), a].each { |d| stamp(d, 1) }
    b =File.join(@projects, 'beta')
    put(File.join(b, 'b.rb'), 6)
    stamp(b, 2)
    put(File.join(@projects, 'loose-file.txt'), 20)
    init_hub

    rows = recent_json('projects')
    assert_equal [hub_path('projects', 'beta'), hub_path('projects', 'alpha')], rows.map { |r| r['path'] }
    assert_equal [at(6), at(4)], rows.map { |r| utc_time(r['timestamp']) }
  end

  def test_latest_prints_only_the_path_even_with_spaces
    put(File.join(@notes, 'older.txt'), 2)
    put(File.join(@notes, 'my notes', 'Weekly Plan v2.md'), 6)
    init_hub

    out, err, code = hub('latest', 'docs/notes')
    assert_equal 0, code, err
    assert_equal "#{hub_path('docs', 'notes', 'my notes', 'Weekly Plan v2.md')}\n", out
    assert_equal '', err
  end

  def test_latest_json_is_one_object_and_recent_json_is_an_array
    put(File.join(@notes, 'one.txt'), 2)
    put(File.join(@notes, 'two.txt'), 3)
    init_hub

    out, err, code = hub('latest', 'docs/notes', '--json')
    assert_equal 0, code, err
    object = JSON.parse(out)
    assert_instance_of Hash, object
    assert_equal %w[basis name path timestamp], object.keys.sort
    assert_equal hub_path('docs', 'notes', 'two.txt'), object['path']
    assert_equal Time.utc(2026, 1, 3, 12), Time.iso8601(object['timestamp'])
    assert_equal 'modified', object['basis']
    assert_instance_of Array, recent_json('docs/notes')
  end

  def test_recent_paths_emits_one_path_per_line
    put(File.join(@notes, 'a b.txt'), 2)
    put(File.join(@notes, 'c.txt'), 3)
    init_hub

    out, err, code = hub('recent', 'docs/notes', '--paths')
    assert_equal 0, code, err
    assert_equal [hub_path('docs', 'notes', 'c.txt'), hub_path('docs', 'notes', 'a b.txt')], out.lines.map(&:chomp)
    _, _, code = hub('recent', 'docs/notes', '--paths', '--json')
    refute_equal 0, code
  end

  def test_empty_results
    init_hub
    out, err, code = hub('recent', 'docs/notes', '--json')
    assert_equal 0, code, err
    assert_equal [], JSON.parse(out)
    out, _, code = hub('recent', 'docs/notes', '--paths')
    assert_equal [0, ''], [code, out]

    %w[latest].each do
      out, err, code = hub('latest', 'docs/notes')
      refute_equal 0, code
      assert_equal '', out
      refute_empty err
      out, err, code = hub('latest', 'docs/notes', '--json')
      refute_equal 0, code
      assert_equal '', out
      refute_empty err
    end
  end

  def test_group_aggregates_leaf_links_and_dedupes_realpaths
    other = File.join(@src, 'other')
    alias_dir = File.join(@src, 'notes-alias')
    put(File.join(@notes, 'n.txt'), 2)
    put(File.join(@notes, 'sub', 's.txt'), 4)
    put(File.join(other, 'o.txt'), 3)
    File.symlink(@notes, alias_dir)
    links = [{ 'name' => 'docs/notes', 'target' => @notes, 'description' => 'N' },
             { 'name' => 'docs/alias', 'target' => alias_dir, 'description' => 'A' },
             { 'name' => 'docs/sub', 'target' => File.join(@notes, 'sub'), 'description' => 'S' },
             { 'name' => 'docs/other', 'target' => other, 'description' => 'O' }]
    init_hub(links)

    rows = recent_json('docs')
    real = rows.map { |r| File.realpath(r['path']) }
    assert_equal real.uniq, real
    assert_equal [File.join(@notes, 'sub', 's.txt'), File.join(other, 'o.txt'), File.join(@notes, 'n.txt')].map { |p| File.realpath(p) }, real
    assert_equal 3, hub('recent', 'docs', '--paths')[0].lines.size
  end

  def test_interior_symlinked_directories_and_cycles_are_not_entered_but_root_symlink_is
    zsh = File.join(@src, 'zsh')
    put(File.join(zsh, 'rc'), 9)
    put(File.join(@notes, 'real.txt'), 2)
    File.symlink(@notes, File.join(@notes, 'cycle'))
    File.symlink(zsh, File.join(@notes, 'interior'))
    linked_root = File.join(@src, 'root-link')
    File.symlink(@notes, linked_root)
    init_hub([{ 'name' => 'docs/notes', 'target' => linked_root, 'description' => 'via symlink' }])

    assert_equal [hub_path('docs', 'notes', 'real.txt')], recent_json('docs/notes').map { |r| r['path'] }
  end

  def test_unavailable_root_and_unreadable_directory_fail_visibly
    put(File.join(@notes, 'a.txt'), 2)
    locked = File.join(@notes, 'locked')
    put(File.join(locked, 'inside.txt'), 3)
    init_hub

    unless Process.uid.zero?
      File.chmod(0o000, locked)
      begin
        out, err, code = hub('recent', 'docs/notes', '--json')
        refute_equal 0, code
        refute_empty err
        refute_equal [], (JSON.parse(out) rescue nil)
        assert_equal '', hub('latest', 'docs/notes')[0]
      ensure
        File.chmod(0o755, locked)
      end
    end

    FileUtils.rm_rf(@notes)
    out, err, code = hub('recent', 'docs/notes', '--json')
    refute_equal 0, code
    refute_empty err
    assert_equal '', out
    _, err, code = hub('latest', 'docs/notes')
    refute_equal 0, code
    refute_empty err
  end

  def test_wrong_flags_and_names_are_usage_errors_with_no_output
    put(File.join(@notes, 'a.txt'), 2)
    init_hub
    [%w[recent docs/notes --repo o/r], %w[latest docs/notes --repo o/r], %w[latest docs/notes --limit 1],
     %w[recent docs/notes --limit 0], %w[recent docs/notes --limit abc], %w[recent docs/notes --limit], %w[latest],
     %w[recent], %w[recent nope], %w[latest nope], %w[recent docs/notes extra]].each do |args|
      out, err, code = hub(*args)
      refute_equal 0, code, args.inspect
      assert_equal '', out, args.inspect
      refute_empty err, args.inspect
    end
    assert_equal 0, hub('find', 'docs/notes', 'a', '--limit', '1')[2]
  end

  def test_sources_are_unchanged_by_every_recency_command
    repo = git_project('alpha')
    put(File.join(repo, 'src', 'new.rb'), 6)
    put(File.join(@notes, 'deep', 'a.txt'), 3)
    put(File.join(@downloads, 'f.bin'), 4)
    File.symlink(@notes, File.join(@notes, 'cycle'))
    init_hub
    before = snapshot(@src)

    %w[docs/notes downloads projects].each do |name|
      hub('recent', name)
      hub('recent', name, '--json')
      hub('recent', name, '--paths', '--limit', '1')
      hub('latest', name)
      hub('latest', name, '--json')
    end
    assert_equal before, snapshot(@src)
    refute File.exist?(File.join(@hub, 'recent')), 'no materialized recent links'
  end
end
