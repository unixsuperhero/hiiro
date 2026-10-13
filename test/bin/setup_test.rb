require 'test_helper'
require 'open3'
require 'rbconfig'
require 'json'
require 'digest'

# `h setup`, `hiiro setup`, and `h update` as fresh processes against a
# sandbox HOME. PATH holds only a ruby link, a fake rbenv, and /usr/bin:/bin.
class SetupTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  COMMANDS = Dir.glob('h-*', base: File.join(ROOT, 'bin')).sort
  PLUGINS = Dir.glob('*.rb', base: File.join(ROOT, 'plugins')).sort

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('hiiro-setup-'))
    @home = File.join(@sandbox, 'home')
    @bin = File.join(@home, 'bin')
    @manifest = File.join(@home, '.config/hiiro/install-manifest.json')
    FileUtils.mkdir_p(@home)
    @tools = File.join(@sandbox, 'tools')
    FileUtils.mkdir_p(@tools)
    File.symlink(RbConfig.ruby, File.join(@tools, 'ruby'))
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_plan_is_read_only_and_apply_installs_every_packaged_asset
    before = snapshot
    out, status = run_cmd('h', 'setup')

    assert_equal 0, status.exitstatus, out
    assert_equal before, snapshot
    assert_equal "Source: hiiro #{Hiiro::VERSION} (checkout #{ROOT})\n", out.lines.first
    assert_includes out, "  missing        ~/bin/h-pr  "
    assert_includes out, "\n#{COMMANDS.size + PLUGINS.size} missing\nRun `h setup --apply` to write #{COMMANDS.size + PLUGINS.size} assets.\n"

    out, status = run_cmd('h', 'setup', '--apply')
    assert_equal 0, status.exitstatus, out
    assert_includes out, "Applied: #{COMMANDS.size + PLUGINS.size} installed\n"
    COMMANDS.each { |name| assert_equal File.binread(File.join(ROOT, 'bin', name)), File.binread(File.join(@bin, name)), name }
    assert_equal 0o755, File.stat(File.join(@bin, 'h-pr')).mode & 0o7777
    assert_equal 0o644, File.stat(File.join(@home, '.config/hiiro/plugins/pins.rb')).mode & 0o7777
    assert_equal({ 'asset' => 'command', 'source' => 'bin/h-task', 'package' => 'hiiro', 'version' => Hiiro::VERSION,
                   'root' => ROOT, 'sha256' => Digest::SHA256.file(File.join(ROOT, 'exe/t')).hexdigest, 'mode' => '0755',
                   'owner' => 'installed', 'link' => '../exe/t' }, manifest[File.join(@bin, 'h-task')])

    out, = run_cmd('h', 'setup')
    assert_includes out, "\n#{COMMANDS.size + PLUGINS.size} unchanged\n"
    refute_match(/missing|updatable/, out)
  end

  def test_both_setup_names_install_their_own_prefix_and_share_plugins
    run_ok('h', 'setup', '--apply')
    out, = run_ok('hiiro', 'setup', '--apply')

    assert_includes out, "Applied: #{COMMANDS.size} installed\n"
    assert_equal File.binread(File.join(ROOT, 'bin/h-pr')), File.binread(File.join(@bin, 'hiiro-pr'))
    assert_equal COMMANDS.size * 2 + PLUGINS.size, manifest.size
    assert_equal 'bin/h-pr', manifest[File.join(@bin, 'hiiro-pr')]['source']
  end

  def test_modified_and_unowned_files_stay_byte_identical
    run_ok('h', 'setup', '--apply', 'h-pr', 'h-bin')
    File.write(File.join(@bin, 'h-pr'), "#!/bin/sh\necho mine\n")
    File.chmod(0o700, File.join(@bin, 'h-pr'))
    File.binwrite(File.join(@bin, 'h-sha'), File.binread(File.join(ROOT, 'bin/h-sha')))
    File.chmod(0o755, File.join(@bin, 'h-sha'))
    kept = %w[h-pr h-sha].to_h { |name| [name, [File.binread(File.join(@bin, name)), File.stat(File.join(@bin, name)).mode]] }

    out, status = run_cmd('h', 'setup', '--apply')

    assert_equal 0, status.exitstatus, out
    assert_includes out, "  user-modified  ~/bin/h-pr"
    assert_includes out, "  collision      ~/bin/h-sha"
    assert_equal kept, %w[h-pr h-sha].to_h { |name| [name, [File.binread(File.join(@bin, name)), File.stat(File.join(@bin, name)).mode]] }
    refute manifest.key?(File.join(@bin, 'h-sha'))

    docs = JSON.parse(run_ok('h', 'bin', 'docs', '--json', path: [@bin]).first)
    assert_equal({ 'pr' => "modified (managed hiiro #{Hiiro::VERSION})", 'sha' => 'user', 'bin' => "managed hiiro #{Hiiro::VERSION}",
                   'setup' => "package hiiro #{Hiiro::VERSION}" },
                 docs.select { |e| %w[pr sha bin setup].include?(e['name']) }.to_h { |e| [e['name'], e['origin']] })
    assert_equal "editing #{@bin}/h-pr (modified (managed hiiro #{Hiiro::VERSION}))\n",
                 run_ok('h', 'edit', 'pr', path: [@bin], env: { 'EDITOR' => '/usr/bin/true' }).first

    out, status = run_cmd('h', 'setup', '--adopt')
    assert_equal [1, "ERROR: --adopt needs the NAME of each file to adopt\n"], [status.exitstatus, out]
    run_ok('h', 'setup', '--adopt', 'h-sha')
    assert_equal 'adopted', manifest[File.join(@bin, 'h-sha')]['owner']
    assert_equal kept['h-sha'], [File.binread(File.join(@bin, 'h-sha')), File.stat(File.join(@bin, 'h-sha')).mode]
  end

  def test_a_failed_write_exits_nonzero_and_is_not_owned
    File.write(File.join(@home, '.config'), "not a directory\n")

    out, status = run_cmd('h', 'setup', '--apply')

    assert_equal 1, status.exitstatus
    assert_match(%r{^  failed    ~/\.config/hiiro/plugins/pins\.rb  \(}, out)
    assert_match(%r{^  failed    ~/bin/h-pr  \(manifest not saved: }, out)
    assert_includes out, "\nApplied: #{COMMANDS.size + PLUGINS.size} failed\n"
    refute File.exist?(@manifest)
  end

  def test_update_installs_per_ruby_then_applies_shared_assets_once
    log = File.join(@sandbox, 'rbenv.log')
    state = File.join(@sandbox, 'gems')
    FileUtils.mkdir_p(state)
    rbenv = File.join(@tools, 'rbenv')
    File.write(rbenv, <<~SH)
      #!/bin/bash
      echo "$* @$RBENV_VERSION" >> #{log}
      case "$1" in
        versions) printf '2.7.8\\n3.3.10\\n3.4.9\\n' ;;
        version-name) echo 3.3.10 ;;
        exec) shift
          case "$1 $2" in
            "ruby -e") printf '%s' "$RBENV_VERSION" ;;
            "gem install") [ "$RBENV_VERSION" = 3.4.9 ] && exit 2; touch #{state}/$RBENV_VERSION ;;
            "gem list") [ -e #{state}/$RBENV_VERSION ] && echo "hiiro (#{Hiiro::VERSION}, 0.0.1)" || echo "hiiro (0.0.1)" ;;
            h\\ *) shift; exec #{File.join(ROOT, 'exe/h')} "$@" ;;
            *) exit 99 ;;
          esac ;;
        *) exit 99 ;;
      esac
    SH
    File.chmod(0o755, rbenv)

    out, status = run_cmd('h', 'update', '-a')

    assert_equal 1, status.exitstatus
    assert_equal <<~OUT, out.lines.first(5).join
      Updating hiiro in 2 compatible Ruby version(s)
        ruby 2.7.8  skipped (requires Ruby #{Hiiro::SUPPORTED_RUBY_VERSION})
        ruby 3.3.10  →  hiiro #{Hiiro::VERSION}
        ruby 3.4.9  →  hiiro 0.0.1  (gem install failed)
      Shared assets: hiiro #{Hiiro::VERSION} from ruby 3.3.10
    OUT
    assert_includes out, "Applied: #{COMMANDS.size + PLUGINS.size} installed\n"
    calls = File.readlines(log, chomp: true)
    assert_equal ['exec gem install hiiro -u @3.3.10', 'exec gem install hiiro -u @3.4.9'], calls.grep(/gem install/).sort
    assert_equal ['exec h setup --apply @3.3.10'], calls.grep(/exec h /)
  end

  private

  def manifest = JSON.parse(File.read(@manifest))['assets']

  def snapshot
    Dir.glob('**/*', File::FNM_DOTMATCH, base: @home).reject { |p| p.end_with?('.') }.sort
  end

  def run_cmd(*argv, path: [], env: {})
    env = env.merge(
      'HOME' => @home, 'PATH' => [@tools, *path, '/usr/bin', '/bin'].join(':'),
      'LANG' => 'en_US.UTF-8', 'TZ' => 'UTC',
      'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'BUNDLE_PATH' => ENV['BUNDLE_PATH'],
      'RUBYOPT' => "-rbundler/setup -I#{LIB}", 'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL
    ).compact
    command = [File.join(ROOT, argv.first == 'h' || argv.first == 'hiiro' ? 'exe' : 'bin', argv.first), *argv.drop(1)]
    stdout, stderr, status = Open3.capture3(env, *command, chdir: @sandbox, unsetenv_others: true)
    [stdout + stderr, status]
  end

  def run_ok(*argv, **opts)
    out, status = run_cmd(*argv, **opts)
    assert status.success?, "#{argv.join(' ')} failed (#{status.exitstatus}): #{out}"
    [out, status]
  end
end
