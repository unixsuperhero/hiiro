require 'test_helper'
require 'open3'
require 'rbconfig'

class ExtractTest < Minitest::Test
  BIN = File.expand_path('../../bin/h-extract', __dir__)
  LIB = File.expand_path('../../lib', __dir__)

  def setup
    @root = Dir.mktmpdir('h-extract-')
    @cwd = File.join(@root, 'cwd')
    FileUtils.mkdir_p(@cwd)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_checked_files_and_directories_use_actual_filesystem_types
    write_file('README')
    write_file('src/app.rb')
    make_dir('docs')
    make_dir('release.v1')
    input = "README docs src/app.rb release.v1 missing.rb missing/ src/app.rb docs/\n"

    assert_equal "README\nsrc/app.rb\n", extract('files', input: input)
    assert_equal "docs\nrelease.v1\ndocs/\n", extract('dirs', input: input)
  end

  def test_repeated_bases_replace_cwd_and_accept_matches_in_any_base
    write_file('cwd-only.txt')
    make_dir('cwd-dir')
    write_file('first/only-one.txt')
    write_file('second/only-two.txt')
    make_dir('first/shared')
    write_file('second/shared')
    make_dir('first/only-one-dir')
    make_dir('second/only-two-dir')
    write_file('first/mixed')
    make_dir('second/mixed')
    bases = ['--base-dir', 'first', '-b', 'second', '--base-dir', 'first']

    assert_equal "only-two.txt\nonly-one.txt\nshared\n",
      extract('files', *bases,
        input: "cwd-only.txt only-two.txt only-one.txt shared only-two.txt\n")
    assert_equal "only-two-dir\nonly-one-dir\nmixed\n",
      extract('dirs', *bases,
        input: "cwd-dir only-two-dir only-one-dir mixed only-two-dir\n")
  end

  def test_checked_paths_strip_quotes_and_locations_but_preserve_spelling
    write_file('src/app.rb')
    write_file('two words.txt')
    make_dir('folder with spaces')
    input = <<~'TEXT'
      `src/app.rb:12:3` (./src/app.rb:8) "two words.txt:4:2"
      'two words.txt' "folder with spaces:9:1" `folder with spaces`
    TEXT

    assert_equal "src/app.rb\n./src/app.rb\ntwo words.txt\n",
      extract('files', input: input)
    assert_equal "folder with spaces\n", extract('dirs', input: input)
  end

  def test_apostrophes_in_prose_and_existing_punctuation_do_not_hide_files
    write_file('src/app.rb')
    write_file('notes!')
    assert_equal "src/app.rb\nnotes!\n",
      extract('files', input: "Don't lose src/app.rb, or 'notes!' in prose.")
  end

  def test_absolute_and_home_paths_ignore_relative_lookup_bases
    write_file('notes.txt')
    absolute = File.join(@cwd, 'notes.txt')
    stdout, stderr, status = Open3.capture3(
      { 'HIIRO_TEST_DB' => 'sqlite::memory:', 'HOME' => @cwd },
      RbConfig.ruby, '-I', LIB, BIN, 'files', '-b', 'missing-base',
      stdin_data: "#{absolute} ~/notes.txt", chdir: @cwd
    )
    assert status.success?, stderr
    assert_equal "#{absolute}\n~/notes.txt\n", stdout
  end

  def test_urls_do_not_leak_paths_into_file_or_directory_output
    write_file('example.test/src/app.rb')
    write_file('src/app.rb')
    make_dir('docs')
    input = <<~TEXT
      https://example.test/src/app.rb http://example.test/docs/
      src/app.rb docs/
    TEXT

    assert_equal "src/app.rb\n", extract('files', input: input)
    assert_equal "docs/\n", extract('dirs', input: input)
    assert_equal "src/app.rb\n", extract('files', '--no-check', input: input)
    assert_equal "docs/\n", extract('dirs', '--no-check', input: input)
  end

  def test_unchecked_files_and_directories_follow_distinct_path_heuristics
    input = <<~'TEXT'
      README missing.txt src/missing.rb src/bin docs/ cache.v1/
      cache.v1/name "folder with spaces/item.txt" 'folder with spaces/'
      missing.txt
    TEXT

    assert_equal "missing.txt\nsrc/missing.rb\nsrc/bin\ncache.v1/name\nfolder with spaces/item.txt\n",
      extract('files', '--no-check', input: input)
    assert_equal "src/bin\ndocs/\ncache.v1/name\nfolder with spaces/\n",
      extract('dirs', '--no-check', input: input)
  end

  def test_links_strip_markdown_and_punctuation_preserving_balanced_parentheses
    input = <<~'TEXT'
      [guide](https://example.test/Function_(math)).
      <http://example.test/search?q=a%20b&sort=asc#results>,
      "https://example.test/Function_(math)"
      (https://example.test/plain); https://example.test/last!?
      ftp://example.test/ignored
    TEXT

    assert_equal "https://example.test/Function_(math)\nhttp://example.test/search?q=a%20b&sort=asc#results\nhttps://example.test/plain\nhttps://example.test/last\n",
      extract('links', input: input)
  end

  def test_multiple_input_files_and_explicit_stdin_preserve_encounter_order
    write_file('first.txt', "z.txt a.txt\n")
    write_file('second.txt', "a.txt m.txt\n")

    assert_equal "z.txt\na.txt\nb.txt\nm.txt\n",
      extract('files', '--no-check', 'first.txt', '-', 'second.txt',
        input: "b.txt z.txt\n")
    assert_equal "z.txt\na.txt\nm.txt\n",
      extract('files', '--no-check', 'first.txt', 'second.txt',
        input: "ignored.txt\n")
  end

  private

  def extract(*args, input: '')
    stdout, stderr, status = Open3.capture3(
      { 'HIIRO_TEST_DB' => 'sqlite::memory:' },
      RbConfig.ruby, '-I', LIB, BIN, *args,
      stdin_data: input, chdir: @cwd
    )
    assert status.success?, "h-extract #{args.join(' ')} failed (#{status.exitstatus}):\n#{stdout}#{stderr}"
    stdout
  end

  def write_file(path, content = '')
    full_path = File.join(@cwd, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def make_dir(path)
    FileUtils.mkdir_p(File.join(@cwd, path))
  end
end
