require 'test_helper'

class FilesystemEffectsTest < Minitest::Test
  def test_null_filesystem_records_writes
    fs = Hiiro::Effects::NullFilesystem.new
    fs.write('/tmp/test.yml', 'content: true')
    assert_equal ['/tmp/test.yml'], fs.writes
    assert_equal 'content: true', fs.content_at('/tmp/test.yml')
  end

  def test_null_filesystem_read_raises_on_missing
    fs = Hiiro::Effects::NullFilesystem.new
    assert_raises(Errno::ENOENT) { fs.read('/nonexistent') }
  end

  def test_null_filesystem_exist_returns_false_then_true
    fs = Hiiro::Effects::NullFilesystem.new
    refute fs.exist?('/tmp/x.yml')
    fs.write('/tmp/x.yml', 'hello')
    assert fs.exist?('/tmp/x.yml')
  end
end
