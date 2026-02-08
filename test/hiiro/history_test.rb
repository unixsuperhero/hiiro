require "test_helper"

class HistoryEntryTest < Minitest::Test
  def test_entry_initializes_from_hash
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-01T12:00:00+00:00',
      'cmd' => 'h task ls',
      'pwd' => '/home/user/project',
      'git_branch' => 'main',
      'task' => 'feature-x',
    }
    entry = Hiiro::History::Entry.new(data)

    assert_equal '20240101120000-1234', entry.id
    assert_equal '2024-01-01T12:00:00+00:00', entry.timestamp
    assert_equal 'h task ls', entry.cmd
    assert_equal '/home/user/project', entry.pwd
    assert_equal 'main', entry.git_branch
    assert_equal 'feature-x', entry.task
  end

  def test_entry_to_h
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-01T12:00:00+00:00',
      'cmd' => 'h task ls',
    }
    entry = Hiiro::History::Entry.new(data)

    hash = entry.to_h
    assert_equal '20240101120000-1234', hash['id']
    assert_equal '2024-01-01T12:00:00+00:00', hash['timestamp']
    assert_equal 'h task ls', hash['cmd']
    refute hash.key?('pwd')
  end

  def test_entry_state_key_excludes_metadata
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-01T12:00:00+00:00',
      'cmd' => 'h task ls',
      'pwd' => '/home/user/project',
      'git_branch' => 'main',
    }
    entry = Hiiro::History::Entry.new(data)

    state = entry.state_key
    refute state.key?('id')
    refute state.key?('timestamp')
    refute state.key?('cmd')
    assert_equal '/home/user/project', state['pwd']
    assert_equal 'main', state['git_branch']
  end

  def test_entry_matches_single_filter
    data = {
      'id' => '20240101120000-1234',
      'git_branch' => 'main',
      'task' => 'feature-x',
    }
    entry = Hiiro::History::Entry.new(data)

    assert entry.matches?(git_branch: 'main')
    refute entry.matches?(git_branch: 'develop')
  end

  def test_entry_matches_multiple_filters
    data = {
      'id' => '20240101120000-1234',
      'git_branch' => 'main',
      'task' => 'feature-x',
    }
    entry = Hiiro::History::Entry.new(data)

    assert entry.matches?(git_branch: 'main', task: 'feature-x')
    refute entry.matches?(git_branch: 'main', task: 'feature-y')
  end

  def test_entry_matches_with_nil_filter
    data = {
      'id' => '20240101120000-1234',
      'git_branch' => 'main',
    }
    entry = Hiiro::History::Entry.new(data)

    assert entry.matches?(git_branch: 'main', task: nil)
  end

  def test_entry_matches_array_filter
    data = {
      'id' => '20240101120000-1234',
      'git_branch' => 'main',
    }
    entry = Hiiro::History::Entry.new(data)

    assert entry.matches?(git_branch: %w[main develop])
    refute entry.matches?(git_branch: %w[feature release])
  end

  def test_entry_oneline_format
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-15T10:30:00+00:00',
      'git_sha' => 'abc1234567890',
      'git_branch' => 'main',
      'task' => 'feature-x',
      'cmd' => 'h task switch',
    }
    entry = Hiiro::History::Entry.new(data)

    line = entry.oneline(1)
    assert_includes line, "01/15"
    assert_includes line, "abc1234"
    assert_includes line, "[main]"
    assert_includes line, "(feature-x)"
  end

  def test_entry_oneline_truncates_long_cmd
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-15T10:30:00+00:00',
      'cmd' => 'this is a very long command that should be truncated to fit the display',
    }
    entry = Hiiro::History::Entry.new(data)

    line = entry.oneline
    assert_includes line, "..."
    assert line.include?("this is a very")
  end

  def test_entry_full_display
    data = {
      'id' => '20240101120000-1234',
      'timestamp' => '2024-01-15T10:30:00+00:00',
      'description' => 'Test entry',
      'cmd' => 'h task ls',
      'pwd' => '/home/user/project',
      'git_branch' => 'main',
      'git_sha' => 'abc1234567890',
      'task' => 'feature-x',
    }
    entry = Hiiro::History::Entry.new(data)

    display = entry.full_display
    assert_includes display, "ID:"
    assert_includes display, "20240101120000-1234"
    assert_includes display, "Description:"
    assert_includes display, "Test entry"
    assert_includes display, "Git:"
    assert_includes display, "main"
    assert_includes display, "Task:"
    assert_includes display, "feature-x"
  end

  def test_entry_handles_nil_data
    entry = Hiiro::History::Entry.new(nil)

    assert_nil entry.id
    assert_nil entry.cmd
    assert_nil entry.git_branch
  end
end
