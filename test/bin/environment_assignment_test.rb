require 'test_helper'
require_relative '../support/cli_sandbox'

# `h env add` and `h export add` write through one EnvironmentAssignment:
# literal values, an explicit destination policy, append-only writes.
class EnvironmentAssignmentTest < Minitest::Test
  include CliSandbox

  def setup = setup_sandbox
  def teardown = teardown_sandbox

  def zshenv = File.join(@home, '.zshenv')
  def mode(path) = File.stat(path).mode & 0o777

  def test_values_are_written_literally_to_zshenv_created_0600
    assert_equal ["Added environment variable to #{zshenv}\n", '', 0], run_bin('h-env', 'add', 'Q', 'say "hi"')
    run_bin('h-env', 'add', 'D', '$HOME `id` $(id -u)')
    run_bin('h-env', 'add', 'B', 'C:\tmp\\')
    assert_equal "export Q=\"say \\\"hi\\\"\"\nexport D=\"\\$HOME \\`id\\` \\$(id -u)\"\nexport B=\"C:\\\\tmp\\\\\"\n", File.binread(zshenv)
    assert_equal 0o600, mode(zshenv)
    out, = Open3.capture2({ 'HOME' => @home }, '/bin/sh', '-c', ". #{zshenv}; printf '%s|%s|%s' \"$Q\" \"$D\" \"$B\"")
    assert_equal 'say "hi"|$HOME `id` $(id -u)|C:\tmp\\', out
    refute File.exist?(File.join(@home, '.zshrc'))
  end

  def test_vars_module_file_without_final_newline_keeps_bytes_and_mode
    dir = File.join(@home, '.zshenv.d')
    FileUtils.mkdir_p(dir)
    vars = File.join(dir, 'vars.zsh')
    File.write(vars, 'export OLD="x"')
    File.chmod(0o644, vars)
    assert_equal ["Added environment variable to #{vars}\n", 0], run_bin('h-export', 'add', 'NEW', 'v', 'w').values_at(0, 2)
    assert_equal "export OLD=\"x\"\nexport NEW=\"v w\"\n", File.binread(vars)
    assert_equal 0o644, mode(vars)
    refute File.exist?(zshenv)
  end

  def test_explicit_file_wins
    custom = File.join(@root, 'custom.zsh')
    assert_equal 0, run_bin('h-env', 'add', '--file', custom, '--', 'X', '--flaglike').last
    assert_equal "export X=\"--flaglike\"\n", File.binread(custom)
    assert_equal 0o600, mode(custom)
  end

  def test_invalid_names_values_and_usage_leave_files_untouched
    ['1X', 'A-B', ''].each do |name|
      assert_equal ['', "Invalid environment variable name\n", 1], run_bin('h-env', 'add', name, 'v')
    end
    assert_equal ['', "Environment variable value cannot contain a newline\n", 1], run_bin('h-env', 'add', 'N', "a\nb")
    assert_equal ['', "Usage: h env add [--file PATH] NAME VALUE\n", 1], run_bin('h-env', 'add', 'ONLY')
    assert_equal ['', "Usage: h env add [--file PATH] NAME VALUE\n", 1], run_bin('h-env', 'add', 'A', 'b', 'c')
    assert_equal ['', "Usage: h export add [--file PATH] NAME WORDS...\n", 1], run_bin('h-export', 'add', 'ONLY')
    refute File.exist?(zshenv)
  end
end
