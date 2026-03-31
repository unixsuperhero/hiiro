require 'test_helper'

class FilesystemEffectsTest < Minitest::Test
  def setup
    @fs = Hiiro::Effects::NullFilesystem.new
  end

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

  def test_todo_manager_writes_yaml_when_dual_write_active
    skip "dual-write disabled" unless Hiiro::DB.dual_write?

    mgr = Hiiro::TodoManager.new(fs: @fs)
    mgr.add("test todo")

    assert_includes @fs.writes, Hiiro::TodoManager::TODO_FILE
    yaml = YAML.safe_load(@fs.content_at(Hiiro::TodoManager::TODO_FILE))
    assert yaml['todos'].any? { |t| t['text'] == 'test todo' }
  end

  def test_todo_manager_no_write_when_dual_write_disabled
    Hiiro::DB.disable_dual_write!
    refute Hiiro::DB.dual_write?

    mgr = Hiiro::TodoManager.new(fs: @fs)
    mgr.add("no write todo")

    assert_empty @fs.writes
  ensure
    # Re-enable dual-write for subsequent tests by removing the migration row
    Hiiro::DB.connection[:schema_migrations].where(name: 'full_migration').delete
  end

  def test_tags_writes_yaml_backup_on_add
    skip "dual-write disabled" unless Hiiro::DB.dual_write?

    tags = Hiiro::Tags.new(:branch, fs: @fs)
    tags.add('my-branch', 'oncall')

    assert_includes @fs.writes, Hiiro::Tags::FILE
  end

  def test_tags_no_write_when_dual_write_disabled
    Hiiro::DB.disable_dual_write!
    refute Hiiro::DB.dual_write?

    tags = Hiiro::Tags.new(:branch, fs: @fs)
    tags.add('my-branch', 'oncall')

    assert_empty @fs.writes
  ensure
    Hiiro::DB.connection[:schema_migrations].where(name: 'full_migration').delete
  end

  def test_projects_writes_yaml_on_save
    skip "dual-write disabled" unless Hiiro::DB.dual_write?

    projects = Hiiro::Projects.new(fs: @fs)
    projects.save_project('myproj', '/home/user/proj/myproj')

    assert_includes @fs.writes, Hiiro::Projects::CONFIG_FILE
  end
end
