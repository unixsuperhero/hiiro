require 'test_helper'
require 'open3'
require 'rbconfig'

class CaptureCommandTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @home = File.realpath(Dir.mktmpdir('capture-home-'))
    @db = File.join(@home, 'hiiro.db')
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def capture(*args, stdin:)
    env = { 'HOME' => @home, 'PATH' => "#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'HIIRO_TEST_DB' => "sqlite://#{@db}" }
    Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', 'h-capture'), *args,
      stdin_data: stdin, binmode: true, chdir: @home, unsetenv_others: true)
  end

  def test_file_capture_preserves_piped_binary_bytes_and_exit_status
    input = (0..255).map(&:chr).join.b * 3 + "\r\n\x00tail".b
    echo = 'STDOUT.binmode; STDIN.binmode; STDOUT.write(STDIN.read); STDOUT.flush; exit 7'
    stdout, stderr, status = capture('file', 'bytes.bin', RbConfig.ruby, '-e', echo, stdin: input)

    assert_equal 7, status.exitstatus
    assert_equal input, stdout.b
    saved = File.join(@home, '.local/share/hiiro/captures/bytes.bin')
    assert_equal input, File.binread(saved)
    assert_match(%r{\[capture saved: #{Regexp.escape(saved)} \(exit 7\)\]}, stderr)

    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal ['bytes.bin', saved, 7], row.values_at(:name, :path, :exit_status)
  end

  def test_unstartable_command_is_recorded_as_127
    _stdout, stderr, status = capture('file', 'missing.log', '/nonexistent/tool', stdin: '')
    assert_equal 127, status.exitstatus
    assert_match(/No such file or directory/, stderr)
    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal 127, row[:exit_status]
  end
end
