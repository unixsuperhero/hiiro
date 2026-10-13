require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "json"

# Runs bin/h-video and bin/h-audio against generated media and reads the
# results back with ffprobe.
class MediaCliTest < Minitest::Test
  BIN_DIR = %w[/opt/homebrew/bin /usr/local/bin].find { |d| File.executable?(File.join(d, "ffmpeg")) && File.executable?(File.join(d, "ffprobe")) }
  ROOT = File.expand_path("../..", __dir__)

  def setup
    skip "ffmpeg/ffprobe not installed" unless BIN_DIR
    @dir = Dir.mktmpdir("media-cli")
    @home = Dir.mktmpdir("media-home")
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x240:rate=25", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
           "-t", "4", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "in.mp4")
  end

  def teardown
    FileUtils.rm_rf([@dir, @home].compact)
  end

  def env(extra = {})
    { "HOME" => @home, "RUBYLIB" => File.join(ROOT, "lib"), "PATH" => "#{BIN_DIR}:/usr/bin:/bin", "HIIRO_TEST_DB" => "sqlite::memory:" }.merge(extra)
  end

  def h(name, *args, **extra)
    Open3.capture3(env(extra), RbConfig.ruby, File.join(ROOT, "bin/h-#{name}"), *args, chdir: @dir, stdin_data: "")
  end

  def ffmpeg(*args)
    _, err, status = Open3.capture3(File.join(BIN_DIR, "ffmpeg"), "-v", "error", "-y", *args, chdir: @dir)
    assert status.success?, err
  end

  def probe(file)
    out, err, status = Open3.capture3(File.join(BIN_DIR, "ffprobe"), "-v", "error", "-show_entries",
                                      "stream=codec_type,codec_name,width,height:format=duration", "-of", "json", file, chdir: @dir)
    assert status.success?, err
    data = JSON.parse(out)
    streams = data["streams"].to_h { |s| [s["codec_type"], s.slice("codec_name", "width", "height").compact] }
    [streams, data.dig("format", "duration").to_f]
  end

  def video(*args)
    _, err, status = h("video", *args)
    assert status.success?, err
  end

  def test_codec_pairs_and_remux
    video("to_mp4", "in.mp4")
    assert_equal({ "video" => { "codec_name" => "h264", "width" => 320, "height" => 240 }, "audio" => { "codec_name" => "aac" } }, probe("in.converted.mp4")[0])
    video("to_webm", "in.mp4")
    assert_equal({ "video" => { "codec_name" => "vp9", "width" => 320, "height" => 240 }, "audio" => { "codec_name" => "opus" } }, probe("in.converted.webm")[0])
    video("to_mkv", "in.mp4")
    assert_equal({ "video" => { "codec_name" => "h264", "width" => 320, "height" => 240 }, "audio" => { "codec_name" => "aac" } }, probe("in.converted.mkv")[0])
  end

  def test_resize_keeps_aspect_with_even_width
    video("resize", "in.mp4", "180")
    assert_equal({ "codec_name" => "h264", "width" => 240, "height" => 180 }, probe("in.180p.mp4")[0]["video"])
    video("resize720", "in.mp4")
    assert_equal({ "codec_name" => "h264", "width" => 960, "height" => 720 }, probe("in.720p.mp4")[0]["video"])
    video("compress_small", "in.mp4")
    assert_equal({ "codec_name" => "h264", "width" => 640, "height" => 480 }, probe("in.small.mp4")[0]["video"])
  end

  def test_clip_uses_duration_clip_to_uses_end_time_and_clip_precise_reencodes
    video("clip", "in.mp4", "1", "2")
    streams, duration = probe("in.clip_1.mp4")
    assert_equal "h264", streams["video"]["codec_name"]
    assert_in_delta 2.0, duration, 0.1

    video("clip_to", "in.mp4", "1", "3.5")
    _, duration = probe("in.clip_1_to_3.5.mp4")
    assert_in_delta 2.5, duration, 0.11

    video("clip_precise", "in.mp4", "1.2", "2")
    streams, duration = probe("in.clip_precise_1.2.mp4")
    assert_equal "h264", streams["video"]["codec_name"]
    assert_equal 2.0, duration
    assert_equal 50, frames("in.clip_precise_1.2.mp4")
    # copy starts at the keyframe before 1.2s; a re-encode starts exactly there
    video("clip", "in.mp4", "1.2", "2")
    refute_equal 50, frames("in.clip_1.2.mp4")
  end

  def frames(file)
    out, = Open3.capture3(File.join(BIN_DIR, "ffprobe"), "-v", "error", "-select_streams", "v", "-count_packets",
                          "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", file, chdir: @dir)
    out.to_i
  end

  def test_audio_extraction_codecs
    { "audio" => ["in.audio.mp3", "mp3"], "audio_wav" => ["in.audio.wav", "pcm_s16le"],
      "audio_aac" => ["in.audio.aac", "aac"], "audio_flac" => ["in.audio.flac", "flac"] }.each do |verb, (file, codec)|
      video(verb, "in.mp4")
      streams, = probe(file)
      assert_equal({ "audio" => { "codec_name" => codec } }, streams, verb)
    end
  end

  def test_missing_argument_is_a_clean_error
    out, err, status = h("video", "clip", "in.mp4", "1")
    refute status.success?
    assert_equal "", out
    assert_equal "ERROR: Missing required argument: duration (seconds or HH:MM:SS)\n", err
  end

  def test_audio_clips_and_length
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "3", "rant.wav")
    _, err, status = h("audio", "clips", "rant.wav", "0", "1", "2.5", "3")
    assert status.success?, err
    assert_equal %w[clip_000.wav clip_001.wav clip_002.wav], Dir.children(@dir).grep(/\Aclip_/).sort
    assert_equal({ "audio" => { "codec_name" => "pcm_s16le" } }, probe("clip_001.wav")[0])

    File.write(File.join(@dir, "notes.txt"), "not media")
    out, err, status = h("audio", "length", "rant.wav", "notes.txt", "missing.wav")
    assert status.success?, err
    assert_equal "File: rant.wav => 3.00\n{:sum=>3.0}\n", out
    assert_equal "notes.txt: no duration\n", err

    out, = h("audio", "encapsulated_length", "rant.wav", "rant.wav")
    assert_equal "File: rant.wav => 3.00\nFile: rant.wav => 3.00\n{:sum=>6.0}\n", out
  end

  def test_transcribe_resolves_the_profile_adapter_only_when_selected
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=440", "-t", "1", "a.wav")
    _, err, status = h("audio", "transcribe", "a.wav")
    refute status.success?
    assert_equal "ERROR: transcribe command not found: mlx_whisper (set transcribe.command in #{@home}/.config/hiiro/profile.yml)\n", err

    FileUtils.mkdir_p(File.join(@home, ".config/hiiro"))
    File.write(File.join(@home, ".config/hiiro/profile.yml"), "transcribe:\n  command: [/bin/echo, whisper-fixture]\n")
    _, err, status = h("audio", "transcribe", "a.wav", "WHISPER_MODEL" => nil)
    refute status.success?
    assert_equal "ERROR: transcribe model is not set (set transcribe.model in #{@home}/.config/hiiro/profile.yml or WHISPER_MODEL)\n", err

    out, err, status = h("audio", "xscribe", "-s", "-j", "a.wav", "WHISPER_MODEL" => "tiny")
    assert status.success?, err
    assert_equal "whisper-fixture a.wav --model tiny -f srt,json\n", out
  end
end
