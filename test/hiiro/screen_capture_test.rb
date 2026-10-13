require "test_helper"
require "tmpdir"
require "open3"

class ScreenCaptureTest < Minitest::Test
  SC = Hiiro::ScreenCapture
  FFMPEG = %w[/opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg].find { |p| File.executable?(p) } || "ffmpeg"

  def test_normalize_rect_scales_rounds_and_makes_size_even
    assert_equal [0, 25, 1200, 800], SC.normalize_rect([0, 25, 1201, 801], 1)
    assert_equal [10, 51, 2402, 1602], SC.normalize_rect([5, 25.6, 1201.4, 801.2], 2)
    assert_equal [-3, 0, 100, 50], SC.normalize_rect([-3, 0, 101, 51], 1.0)
  end

  def test_audio_and_video_format_validation
    assert_equal "none", SC.audio_mode("none", "all")
    assert_equal "first", SC.audio_mode("0", "first")
    error = assert_raises(Hiiro::Error) { SC.audio_mode("0", "both") }
    assert_equal 'invalid --audio-mode="both"; expected separate, first, all, or none', error.message
    assert_equal "mp4", SC.video_format("MP4")
    error = assert_raises(Hiiro::Error) { SC.video_format("avi") }
    assert_equal 'invalid --video-format="avi"; expected mp4, mkv, or mov', error.message
  end

  def plan(**overrides)
    SC::Plan.new(apps: ["Ghostty", "Code Hiiro!"], rects: [[0, 25, 1200, 800], [1200, 0, 640, 360]],
                 out_dir: "/m", session_name: "yt.20261013-120000", **overrides)
  end

  def test_separate_audio_two_windows_mov
    p = plan
    assert_equal ["/m/yt.20261013-120000-ghostty.mov", "/m/yt.20261013-120000-code-hiiro.mov", "/m/yt.20261013-120000-audio.wav"], p.outputs
    assert_equal "/m/yt.20261013-120000.ffmpeg.log", p.log_file
    assert_equal [
      "ffmpeg", "-hide_banner", "-loglevel", "warning", "-f", "avfoundation", "-capture_cursor", "1", "-capture_mouse_clicks", "1",
      "-framerate", "30", "-i", "1:0",
      "-filter_complex", "[0:v]crop=1200:800:0:25,setpts=PTS-STARTPTS,fps=30,setsar=1[v0];[0:v]crop=640:360:1200:0,setpts=PTS-STARTPTS,fps=30,setsar=1[v1]",
      "-map", "[v0]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "/m/yt.20261013-120000-ghostty.mov",
      "-map", "[v1]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "/m/yt.20261013-120000-code-hiiro.mov",
      "-map", "0:a?", "-vn", "-c:a", "pcm_s16le", "/m/yt.20261013-120000-audio.wav",
    ], p.command
  end

  def test_first_audio_mode_mkv_puts_aac_only_on_first_window
    p = plan(audio_mode: "first", video_format: "mkv", audio: "2", screen: "3", framerate: "60", audio_bitrate: "192k")
    assert_equal ["/m/yt.20261013-120000-ghostty.mkv", "/m/yt.20261013-120000-code-hiiro.mkv"], p.outputs
    cmd = p.command
    assert_equal "3:2", cmd[cmd.index("-i") + 1]
    assert_equal "[0:v]crop=1200:800:0:25,setpts=PTS-STARTPTS,fps=60,setsar=1[v0];[0:v]crop=640:360:1200:0,setpts=PTS-STARTPTS,fps=60,setsar=1[v1]", cmd[cmd.index("-filter_complex") + 1]
    tail = cmd[cmd.index("-filter_complex") + 2..]
    assert_equal [
      "-map", "[v0]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
      "-map", "0:a?", "-c:a", "aac", "-b:a", "192k", "/m/yt.20261013-120000-ghostty.mkv",
      "-map", "[v1]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "/m/yt.20261013-120000-code-hiiro.mkv",
    ], tail
  end

  def test_all_and_none_audio_modes
    all = plan(audio_mode: "all", video_format: "mp4").command
    assert_equal 2, all.each_cons(2).count { |a, b| a == "-c:a" && b == "aac" }
    refute_includes all, "pcm_s16le"
    none = plan(audio: "none", audio_mode: "none").command
    assert_equal "1:none", none[none.index("-i") + 1]
    refute_includes none, "0:a?"
  end

  def test_stop_sends_q_through_the_fifo_and_ffmpeg_finalizes_the_file
    skip "ffmpeg not installed" unless system(FFMPEG, "-version", out: File::NULL, err: File::NULL)
    Dir.mktmpdir("screencap") do |dir|
      out = File.join(dir, "out.mkv")
      fifo = File.join(dir, "ctl.stdin")
      cmd = [FFMPEG, "-hide_banner", "-loglevel", "warning", "-re", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=10", "-c:v", "libx264", out]
      pid = SC::Process.spawn(cmd, control_file: fifo, log_file: File.join(dir, "log"))
      begin
        sleep 1.5
        assert SC::Process.alive?(pid)
        assert_equal :quit, SC::Process.stop(pid, fifo, quit_timeout: 10)
        Process.wait(pid)
        assert_equal 0, $?.exitstatus
        probe, = Open3.capture2(FFMPEG.sub(/ffmpeg\z/, "ffprobe"), "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0", out)
        assert_equal "h264,64,48\n", probe
      ensure
        kill_group(pid)
      end
    end
  end

  def test_stop_falls_back_to_sigint_when_the_process_ignores_the_fifo
    Dir.mktmpdir("screencap") do |dir|
      fifo = File.join(dir, "ctl.stdin")
      pid = SC::Process.spawn(["/bin/sleep", "30"], control_file: fifo, log_file: File.join(dir, "log"))
      begin
        assert_equal :int, SC::Process.stop(pid, fifo, quit_timeout: 0.5, graceful_timeout: 5)
        Process.wait(pid)
        assert_equal "INT", Signal.signame($?.termsig)
      ensure
        kill_group(pid)
      end
    end
  end

  def test_terminate_group_escalates_to_term_then_kill
    Dir.mktmpdir("screencap") do |dir|
      script = "trap '' INT; trap '' TERM; while :; do sleep 0.1; done"
      pid = SC::Process.spawn(["/bin/sh", "-c", script], control_file: File.join(dir, "ctl"), log_file: File.join(dir, "log"))
      begin
        sleep 0.3
        assert_equal :kill, SC::Process.terminate_group(pid, graceful_timeout: 0.5, term_timeout: 0.5)
        Process.wait(pid)
        assert_equal "KILL", Signal.signame($?.termsig)
      ensure
        kill_group(pid)
      end
    end
  end

  private

  def kill_group(pid)
    Process.kill("KILL", -pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
