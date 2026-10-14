require 'test_helper'
require 'open3'
require 'rbconfig'

# Command transitions of step 15, as fresh processes in a sandbox HOME whose
# PATH holds only a ruby link and /usr/bin:/bin.
class ProductScopeTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @sandbox = File.realpath(Dir.mktmpdir('hiiro-scope-'))
    @home = File.join(@sandbox, 'home')
    @tools = File.join(@sandbox, 'tools')
    FileUtils.mkdir_p([@home, @tools])
    File.symlink(RbConfig.ruby, File.join(@tools, 'ruby'))
  end

  def teardown
    FileUtils.remove_entry(@sandbox)
  end

  def test_hiiro_is_the_h_root_without_a_missing_plugin
    out, err, status = run_exe('hiiro', 'ping')
    assert_equal ["pong\n", '', 0], [out, err, status]

    out, err, status = run_exe('hiiro', 'ver')
    assert_equal ["#{Hiiro::VERSION}\n", '', 0], [out, err, status]

    h_help, = run_exe('h')
    hiiro_help, = run_exe('hiiro')
    inline = ->(help) { help.lines.grep(/\(inline\)/).map { |line| line.split(/\s{2,}/)[1] } }
    assert_equal inline.(h_help), inline.(hiiro_help)
    assert_includes inline.(hiiro_help), 'queue'
  end

  def test_removed_commands_do_not_dispatch
    %w[otask osubtask zosubtask .config dsstore dsstore-read uri tags buffer demo].each do |name|
      out, _err, status = run_exe('h', name)
      assert_equal 1, status, name
      assert_equal "Current command: h!\n", out.lines.first, name
    end
  end

  def test_jumplist_without_tmux_fails_before_touching_files
    out, err, status = run_exe('h', 'jumplist', 'ls')
    assert_equal ['', "ERROR: h jumplist needs a running tmux client; none was found\n", 1], [out, err, status]
    assert_empty Dir.children(@home)
  end

  private

  def run_exe(name, *args)
    env = { 'HOME' => @home, 'PATH' => "#{@tools}:#{File.join(ROOT, 'bin')}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
            'HIIRO_TEST_DB' => "sqlite://#{File.join(@sandbox, 'hiiro.db')}", 'RUBYLIB' => File.join(ROOT, 'lib') }
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'exe', name), *args,
                                      chdir: @home, unsetenv_others: true, stdin_data: '')
    [out, err, status.exitstatus]
  end
end
