require "test_helper"

class PsProcessTest < Minitest::Test
  LSOF = <<~OUT
    COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF   NODE NAME
    ruby    12345 josh  cwd    DIR    1,4      640 123456 /Users/josh/proj/app
    ruby    12345 josh    3u  IPv4 0x1234      0t0    TCP *:3000 (LISTEN)
    ruby    12345 josh   12r   REG    1,4     1024 654321 /Users/josh/proj/app/Gemfile
    node    12346 josh  cwd    DIR    1,4      640 123456 /Users/josh/proj/app
  OUT

  def test_open_files_answers_from_one_capture
    of = Hiiro::PsProcess::OpenFiles.new(['-p', '12345'], LSOF)
    assert_equal Set['12345', '12346'], of.pids
    assert_equal '/Users/josh/proj/app', of.cwd
    assert_equal({ fd: '12r', type: 'REG', name: '/Users/josh/proj/app/Gemfile' }, of.files[2])
    assert_equal 4, of.files.size
    assert_equal({ protocol: 'TCP', name: '*:3000' }, of.sockets[1])
    refute of.failed
  end

  def test_open_files_empty_versus_failed
    assert_equal Set[], Hiiro::PsProcess::OpenFiles.new([], "").pids
    assert_nil Hiiro::PsProcess::OpenFiles.new([], "").cwd
    assert Hiiro::PsProcess::OpenFiles.new([], "", failed: true).failed
  end

  def test_snapshot_lookups
    procs = [
      Hiiro::PsProcess.from_line('josh 1 0.0 0.0 1 1 ?? S 1:00 0:00.01 /sbin/launchd'),
      Hiiro::PsProcess.from_line('josh 2 0.0 0.0 1 1 ?? S 1:00 0:00.01 ruby app.rb'),
    ]
    snap = Hiiro::PsProcess::Snapshot.new(procs, captured_at: Time.at(0))
    assert_equal 'ruby app.rb', snap.by_pid(2).cmd
    assert_equal [procs[1]], snap.with_pids(Set['2'])
    assert_equal [procs[1]], snap.matching('ruby')
    assert_equal Time.at(0), snap.captured_at
  end
end
