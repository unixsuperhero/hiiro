require 'test_helper'
require_relative '../support/cli_sandbox'

# h home, h dotfiles, h vim, and h plugin share one DirectoryProfile
# registration. These run the real bins with fixture tools that log their
# argv and working directory.
class DirectoryProfileTest < Minitest::Test
  include CliSandbox

  def setup
    setup_sandbox
    %w[rg skf editor open].each { |tool| recorder(tool) }
    @dotfiles = File.join(@home, 'proj/home')
    @nvim = File.join(@home, '.config/nvim')
    @plugins = File.join(@home, '.config/hiiro/plugins')
    FileUtils.mkdir_p([@dotfiles, @nvim, File.join(@plugins, 'sub'), File.join(@home, 'bin')])
    %w[.config/nvim/init.lua .config/hiiro/plugins/pins.rb .config/hiiro/plugins/tasks.rb
       .config/hiiro/plugins/sub/pinx.rb bin/h-foo bin/h-bar bin/other].each { |rel| File.write(File.join(@home, rel), '') }
  end

  def teardown = teardown_sandbox

  def test_path_prints_each_root_without_a_newline
    { 'h-home' => @home, 'h-dotfiles' => @dotfiles, 'h-vim' => @nvim, 'h-plugin' => @plugins }.each do |bin, root|
      assert_equal [root, '', 0], run_bin(bin, 'path'), bin
    end
    FileUtils.rm_rf(@dotfiles)
    assert_equal [@dotfiles, '', 0], run_bin('h-dotfiles', 'path')
  end

  def test_home_abspath_is_the_resolved_root_and_ignores_task_directories
    link = File.join(@root, 'linked-home')
    File.symlink(@home, link)
    cwd = File.join(@root, 'code')
    FileUtils.mkdir_p(cwd)
    ruby_in_sandbox("%w[mount-alpha mount-beta].each { |n| Hiiro::TaskRecord.create(name: n, primary_directory: #{cwd.inspect}) }")

    assert_equal [link, '', 0], run_bin('h-home', 'path', chdir: cwd, env: { 'HOME' => link })
    assert_equal [@home, '', 0], run_bin('h-home', 'abspath', chdir: cwd, env: { 'HOME' => link })
  end

  def test_search_tools_run_in_the_root_with_their_flags
    %w[h-home h-dotfiles h-vim h-plugin].each do |bin|
      run_bin(bin, 'rg', '-i', 'needle')
      run_bin(bin, 'rgall', 'needle')
    end
    %w[h-home h-dotfiles h-vim].each { |bin| run_bin(bin, 'skf', 'q') }

    roots = [@home, @dotfiles, @nvim, @plugins]
    assert_equal roots.flat_map { |root| ["-S -i needle | cwd=#{root}", "-S --no-ignore-vcs needle | cwd=#{root}"] }, log('rg').lines(chomp: true)
    assert_equal roots.first(3).map { |root| "q | cwd=#{root}" }, log('skf').lines(chomp: true)

    out, _, status = run_bin('h-plugin', 'skf')
    assert_equal 1, status
    assert_includes out, 'Subcommand required for h-plugin'
  end

  def test_a_missing_root_fails_before_running_anything
    FileUtils.rm_rf(@dotfiles)
    assert_equal ['', "ERROR: Directory does not exist: #{@dotfiles}\n", 1], run_bin('h-dotfiles', 'rg', 'x')
    assert_equal '', log('rg')
  end

  def test_edit_actions
    %w[h-home h-dotfiles h-vim h-plugin].each { |bin| run_bin(bin, 'edit') }
    run_bin('h-vim', 'init')
    run_bin('h-vim', 'config')
    run_bin('h-home', 'ebin', 'h-', 'oth*')
    run_bin('h-dotfiles', 'ebin', 'some/file', chdir: @root)
    run_bin('h-plugin', 'edit', 'pin')

    assert_equal [
      *%w[h-home h-dotfiles h-vim h-plugin].map { |bin| "#{ROOT}/bin/#{bin} | cwd=#{@home}" },
      "init.lua | cwd=#{@nvim}",
      "init.lua | cwd=#{@nvim}",
      "h-bar h-foo other | cwd=#{@home}/bin",
      "some/file | cwd=#{@root}",
      "#{@plugins}/pins.rb #{@plugins}/sub/pinx.rb | cwd=#{@home}",
    ], log('editor').lines(chomp: true)

    assert_equal ["No matching plugins found for: \"zz\"\n", '', 0], run_bin('h-plugin', 'edit', 'zz')
  end

  def test_plugin_ls_lists_every_file_under_the_root
    expected = %w[pins.rb sub sub/pinx.rb tasks.rb].map { |rel| "#{@plugins}/#{rel}\n" }.join
    assert_equal [expected, '', 0], run_bin('h-plugin', 'ls')
  end

  def test_home_open_hands_the_root_to_the_opener
    run_bin('h-home', 'open')
    assert_equal "#{@home} | cwd=#{@home}\n", log('open')
  end

  def test_vim_session_starts_a_tmux_session_in_the_root_then_attaches
    recorder('tmux', 'case "$1" in has-session) exit 1 ;; esac')
    assert_equal ['', '', 0], run_bin('h-vim', 'session')
    assert_equal ["has-session -t vim | cwd=#{@home}", "new-session -d -s vim -c #{@nvim} | cwd=#{@home}",
                  "attach-session -t vim | cwd=#{@home}"], log('tmux').lines(chomp: true)

    File.delete(File.join(@root, 'tmux.log'))
    recorder('tmux')
    run_bin('h-vim', 'tmux', env: { 'TMUX' => '/tmp/fake,1,0' })
    assert_equal ["has-session -t vim | cwd=#{@home}", "switch-client -t vim | cwd=#{@home}"], log('tmux').lines(chomp: true)
  end

  def test_vim_session_without_tmux_is_an_error
    assert_equal ['', "ERROR: tmux not found\n", 1], run_bin('h-vim', 'session')
  end
end
