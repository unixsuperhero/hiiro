require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'digest'

# Fresh processes: test_helper has already loaded persistence in this one.
class LazyBootTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('hiiro-lazy-boot-'))
    @home = File.join(@sandbox, 'home')
    @config = File.join(@home, '.config/hiiro')
    @db = File.join(@config, 'hiiro.db')
    @ran = File.join(@sandbox, 'ran.log')
    @edited = File.join(@sandbox, 'edited.log')
    @ruby_dir = dir('ruby')
    File.symlink(RbConfig.ruby, File.join(@ruby_dir, 'ruby'))
    @first = dir('first')
    @second = dir('second')
    FileUtils.mkdir_p(@config)
    File.write(File.join(@config, 'todo.yml'), "todos:\n- id: 1\n  text: legacy\n")
    File.write(File.join(@config, 'links.yml'), "- url: https://example.com\n")
    @editor = script(dir('editor'), 'record-editor', %(printf '%s\\n' "$@" >> #{@edited}))
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_import_help_completion_and_docs_create_nothing
    before = snapshot

    out, = run_ok('ruby', '-e', 'require "hiiro"; print [defined?(Sequel), Hiiro::Runtime.active?, Hiiro::Config.plugin_dir.end_with?("/plugins")].inspect')
    assert_equal '[nil, false, true]', out

    out, status = run_cmd('h')
    assert_equal 1, status.exitstatus
    assert_match(/^  ping\s+\(inline\)\s+\$\S+\/root_commands\.rb:\d+$/, out)
    assert_match(/^  service, svc\s+\[\*svc_args\]\s+\(inline\)/, out)
    assert_match(/^  bin\s+\(external\)\s+\$\S+\/h-bin$/, out)

    out, status = run_cmd('h', 'queue')
    assert_equal [1, "Current command: h-queue!\n"], [status.exitstatus, out.lines.first]
    out, = run_cmd('h', 'svc')
    assert_equal "Current command: h-service!\n", out.lines.first
    out, = run_cmd('h', 'version', '--help')
    assert_equal "-a, --all             Show the version of hiiro for all versions of ruby installed\n-h, --help            Show this help message\n", out
    out, = run_cmd('t', '--help')
    assert_equal "Current command: t!\n", out.lines.first
    out, = run_cmd('t', 'todo', '--help')
    assert_equal "Current command: t-todo!\n", out.lines.first

    assert_equal "pr\npr-monitor\nproject\npry\n", run_ok('h', 'bin', 'complete', 'pr').first
    docs, = run_ok('h', 'bin', 'docs')
    assert_includes docs, "| service | svc | inline | [*svc_args] | #{LIB}/hiiro/root_commands.rb:"
    entries = JSON.parse(run_ok('h', 'bin', 'docs', '--json').first)
    assert_equal({ 'name' => 'pr-monitor', 'kind' => 'external', 'source' => File.join(ROOT, 'bin/h-pr-monitor'),
                   'aliases' => [], 'arguments' => nil, 'shadowed' => [] }, entries.find { |e| e['name'] == 'pr-monitor' })

    assert_equal before, snapshot
    refute File.exist?(@db)
  end

  def test_dispatch_edit_completion_and_ambiguity_share_one_winner
    winner = script(@first, 'h-zqa', %(echo "first $*" >> #{@ran}))
    loser = script(@second, 'h-zqa', %(echo "second $*" >> #{@ran}))
    script(@second, 'h-zqb', %(echo "zqb $*" >> #{@ran}))
    svc = script(@second, 'h-svc', %(echo "svc $*" >> #{@ran}))
    File.write(File.join(@first, 'h-zqplain'), "#!/bin/sh\necho plain >> #{@ran}\n")
    FileUtils.mkdir(File.join(@first, 'h-zqdir'))
    File.chmod(0o755, File.join(@first, 'h-zqdir'))
    File.symlink(File.join(@first, 'gone'), File.join(@first, 'h-zqbroken'))
    before = snapshot

    listing, = run_ok('h', 'bin', 'list', 'zq')
    rows = listing.lines.map(&:chomp).grep(/\A  \S/)
    assert_equal 2, rows.size, listing
    assert_match(/\A  zqa\s+\(external\)\s+\S+first\/h-zqa\z/, rows[0])
    assert_match(/\A  zqb\s+\(external\)\s+\S+second\/h-zqb\z/, rows[1])
    assert_match(/\A\s+shadows external \S+second\/h-zqa\z/, listing.lines.grep(/shadows/).join.chomp)
    zqa = JSON.parse(run_ok('h', 'bin', 'docs', '--json').first).find { |e| e['name'] == 'zqa' }
    assert_equal [winner, [loser]], [zqa['source'], zqa['shadowed'].map { |c| c['source'] }]
    assert_equal "zqa\nzqb\n", run_ok('h', 'bin', 'complete', 'zq').first
    refute File.exist?(@ran)

    out, status = run_cmd('h', 'zq')
    assert_equal 1, status.exitstatus
    assert_match(/Ambiguous subcommand "zq"!/, out)
    refute File.exist?(@ran)

    run_ok('h', 'zqa', 'one')
    run_ok('h', 'zqb', 'two')
    run_ok('h', 'svc', 'three')
    assert_equal ["first one", "zqb two", "svc three"], File.readlines(@ran, chomp: true)

    run_ok('h', 'edit', 'zqa')
    run_ok('h', 'bin', 'edit', 'zqa')
    run_ok('h', 'bin', 'edit', 'sv')
    out, status = run_cmd('h', 'edit', 'zq')
    assert_equal [1, "ERROR: Ambiguous h command \"zq\": zqa, zqb\n"], [status.exitstatus, out]
    assert_equal [winner, winner, svc], File.readlines(@edited, chomp: true)

    assert_equal before, snapshot.except('ran.log', 'edited.log')
    refute File.exist?(@db)
  end

  def test_runtime_operation_records_one_root_invocation_with_resolutions
    run_ok('h', 'ping')
    refute File.exist?(@db)

    out, = run_ok('h', 'registry', 'add', 'link', 'docs', 'https://example.com/docs', '--alias', 'd')
    assert_match(/docs/, out)

    db = Sequel.sqlite(@db)
    assert_equal [['link', 'docs', 'https://example.com/docs', 'd']], db[:registry].select_map(%i[resource_type name value short_name])
    invocations = db[:invocations].all
    assert_equal 1, invocations.size
    assert_equal ['h registry add link docs https://example.com/docs --alias d', @sandbox], invocations.first.values_at(:command, :pwd)
    assert_equal [
      [0, 'h', 'registry', '["add","link","docs","https://example.com/docs","--alias","d"]'],
      [1, 'h-registry', 'add', '["link","docs","https://example.com/docs","--alias","d"]']
    ], db[:invocation_resolutions].where(invocation_id: invocations.first[:id]).order(:depth).select_map(%i[depth bin subcmd args_json])
    db.disconnect
    assert_equal "todos:\n- id: 1\n  text: legacy\n", File.read(File.join(@config, 'todo.yml'))
    assert_equal "- url: https://example.com\n", File.read(File.join(@config, 'links.yml'))
  end

  def test_parent_starting_after_a_child_keeps_one_invocation
    child = %(require "hiiro"; Hiiro.init("go", bin_name: "h-kid", builtin_commands: false); Hiiro::Runtime.activate!)
    parent = %(require "hiiro"; Hiiro.init("kid", "go", bin_name: "h", builtin_commands: false); system(#{RbConfig.ruby.inspect}, "-e", #{child.inspect}) or abort; Hiiro::Runtime.activate!)
    run_ok('ruby', '-e', parent)

    db = Sequel.sqlite(@db)
    assert_equal 1, db[:invocations].count
    assert_equal [[0, 'h', 'kid'], [1, 'h-kid', 'go']], db[:invocation_resolutions].order(:depth).select_map(%i[depth bin subcmd])
    db.disconnect
  end

  private

  def dir(name) = File.join(@sandbox, name).tap { |path| FileUtils.mkdir_p(path) }

  def script(dir, name, body)
    File.join(dir, name).tap do |path|
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  # Every file under the sandbox with its digest; HOME holds config, database, and legacy YAML.
  def snapshot
    Dir.glob('**/*', File::FNM_DOTMATCH, base: @sandbox).reject { |p| p.end_with?('.') }.sort.to_h do |path|
      full = File.join(@sandbox, path)
      [path, File.symlink?(full) || File.directory?(full) ? :entry : Digest::SHA256.file(full).hexdigest]
    end
  end

  def run_cmd(*argv)
    env = {
      'HOME' => @home, 'PATH' => [@ruby_dir, @first, @second, File.join(ROOT, 'bin'), '/usr/bin', '/bin'].join(':'),
      'LANG' => 'en_US.UTF-8', 'TZ' => 'UTC', 'EDITOR' => @editor,
      'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'BUNDLE_PATH' => ENV['BUNDLE_PATH'],
      'RUBYOPT' => "-rbundler/setup -I#{LIB}", 'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL
    }.compact
    command = argv.first == 'ruby' ? argv : [File.join(ROOT, %w[h t].include?(argv.first) ? 'exe' : 'bin', argv.first), *argv.drop(1)]
    stdout, stderr, status = Open3.capture3(env, *command, chdir: @sandbox, unsetenv_others: true)
    [stdout + stderr, status]
  end

  def run_ok(*argv)
    out, status = run_cmd(*argv)
    assert status.success?, "#{argv.join(' ')} failed (#{status.exitstatus}): #{out}"
    [out, status]
  end
end
