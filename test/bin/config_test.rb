require 'test_helper'
require_relative '../support/cli_sandbox'

# h config opens each configuration file in $EDITOR from its directory.
class ConfigTest < Minitest::Test
  include CliSandbox

  def setup
    setup_sandbox
    recorder('editor')
    %w[.config/herdr .config/nvim .config/starship .config/git .claude .ssh].each { |rel| FileUtils.mkdir_p(File.join(@home, rel)) }
  end

  def teardown = teardown_sandbox

  def test_each_config_opens_its_file_from_its_directory
    %w[herdr ssh vim zsh profile starship claude].each { |name| assert_equal ['', '', 0], run_bin('h-config', name), name }
    File.write(File.join(@home, '.config/nvim/init.lua'), '')
    run_bin('h-config', 'vim')

    assert_equal [
      "#{@home}/.config/herdr/config.toml | cwd=#{@home}/.config/herdr",
      "#{@home}/.ssh/config | cwd=#{@home}/.ssh",
      "#{@home}/.config/nvim/init.vim | cwd=#{@home}/.config/nvim",
      "#{@home}/.zshrc | cwd=#{@home}",
      "#{@home}/.zprofile | cwd=#{@home}",
      "#{@home}/.config/starship/starship.toml | cwd=#{@home}/.config/starship",
      "#{@home}/.claude/settings.json | cwd=#{@home}/.claude",
      "#{@home}/.config/nvim/init.lua | cwd=#{@home}/.config/nvim",
    ], log('editor').lines(chomp: true)
  end

  def test_herdr_is_registered_once
    out, _, status = run_bin('h-config')
    assert_equal 1, status
    assert_equal 1, out.lines.count { |line| line.match?(/^\s+herdr\s/) }
  end

  def test_git_child_commands_open_global_ignore_and_local_configs
    repo = File.join(@root, 'repo')
    FileUtils.mkdir_p(File.join(repo, 'lib'))
    system('git', 'init', '-q', repo)

    %w[global ignore local].each { |name| assert_equal ['', '', 0], run_bin('h-config', 'git', name, chdir: File.join(repo, 'lib')), name }
    assert_equal ['', '', 0], run_bin('h-config', 'git', 'local', 'extra', chdir: repo)

    assert_equal [
      "#{@home}/.gitconfig | cwd=#{@home}",
      "#{@home}/.config/git/ignore | cwd=#{@home}/.config/git",
      "#{repo}/.git/config | cwd=#{repo}",
      "#{repo}/.git/config | cwd=#{repo}",
    ], log('editor').lines(chomp: true)

    out, _, status = run_bin('h-config', 'git', chdir: repo)
    assert_equal 1, status
    assert_includes out, 'Subcommand required for h-config-git'
  end
end
