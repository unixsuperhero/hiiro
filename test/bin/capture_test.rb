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

  def env = { 'HOME' => @home, 'PATH' => "#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'HIIRO_TEST_DB' => "sqlite://#{@db}" }

  def capture(*args, stdin:)
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

  def test_closed_reader_keeps_every_byte_in_the_file_and_the_childs_status
    script = 'STDOUT.binmode; 64.times { |i| STDOUT.write((i % 256).chr * 16_384) }; exit 5'
    reader, writer = IO.pipe
    pid = Process.spawn(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', 'h-capture'),
                        'file', 'early.bin', RbConfig.ruby, '-e', script,
                        out: writer, err: File::NULL, in: File::NULL, chdir: @home, unsetenv_others: true)
    writer.close
    reader.readpartial(1024)
    reader.close
    _, status = Process.wait2(pid)

    assert_equal 5, status.exitstatus
    expected = (0...64).map { |i| (i % 256).chr * 16_384 }.join.b
    assert_equal expected, File.binread(File.join(@home, '.local/share/hiiro/captures/early.bin'))
    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal ['early.bin', 5, 'failed', nil, 'capture', @home], row.values_at(:name, :exit_status, :outcome, :exit_signal, :source, :cwd)
    assert_match(/\A\d{14}-\h{6}\z/, row[:run_id])
  end

  def test_interrupt_reaches_the_child_and_is_recorded_once
    script = '$stdout.sync = true; puts "started"; sleep 30'
    reader, writer = IO.pipe
    err_reader, err_writer = IO.pipe
    pid = Process.spawn(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', 'h-capture'),
                        'file', 'int.log', RbConfig.ruby, '-e', script,
                        out: writer, err: err_writer, in: File::NULL, chdir: @home, pgroup: true, unsetenv_others: true)
    writer.close
    err_writer.close
    seen = +''
    seen << reader.readpartial(4096) until seen.include?("started\n")
    Process.kill('INT', -pid)
    seen << reader.read
    _, status = Process.wait2(pid)

    assert_equal 130, status.exitstatus
    assert_equal 1, seen.scan('started').size
    saved = File.join(@home, '.local/share/hiiro/captures/int.log')
    assert_match(/\[capture saved: #{Regexp.escape(saved)} \(signal INT, interrupted\)\]/, err_reader.read)
    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal ['interrupted', 130, 'INT'], row.values_at(:outcome, :exit_status, :exit_signal)
    assert_equal seen, File.read(saved)
    assert_match(/\Astarted\n.*in `sleep': Interrupt\n/m, seen)
  end

  def test_unstartable_command_is_recorded_as_127
    _stdout, stderr, status = capture('file', 'missing.log', '/nonexistent/tool', stdin: '')
    assert_equal 127, status.exitstatus
    assert_match(/No such file or directory/, stderr)
    row = Sequel.sqlite(@db) { |db| db[:captures].order(:id).last }
    assert_equal 127, row[:exit_status]
  end
end
