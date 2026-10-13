require "test_helper"

class MediaTest < Minitest::Test
  P = Hiiro::Media::PRESETS

  def test_output_name_keeps_or_replaces_extension_and_drops_directory
    assert_equal "in.720p.mp4", Hiiro::Media.output_name("dir/in.mp4", "720p")
    assert_equal "in.audio.mp3", Hiiro::Media.output_name("in.mov", "audio", "mp3")
    assert_equal "in.audio.wav", Hiiro::Media.output_name("in.mov", "audio", ".wav")
  end

  def test_clip_family_seeks_after_input_and_names_from_times
    assert_equal %w[ffmpeg -i in.mp4 -ss 00:01:30 -t 60 -c copy in.clip_00-01-30.mp4], P[:clip].command(%w[in.mp4 00:01:30 60])
    assert_equal %w[ffmpeg -i in.mp4 -ss 00:01:30 -to 00:02:30 -c copy in.clip_00-01-30_to_00-02-30.mp4], P[:clip_to].command(%w[in.mp4 00:01:30 00:02:30])
    assert_equal %w[ffmpeg -i in.mp4 -ss 90 -t 5 in.clip_precise_90.mp4], P[:clip_precise].command(%w[in.mp4 90 5])
    assert_equal %w[ffmpeg -i in.wav -ss 1 -to 2 -c copy clip_000.wav], P[:clip_to].command(%w[in.wav 1 2 clip_000.wav])
  end

  def test_defaults_apply_only_when_the_parameter_is_absent
    assert_equal %w[ffmpeg -i a.mkv -vf scale=-2:720 a.720p.mkv], P[:resize].command(%w[a.mkv])
    assert_equal %w[ffmpeg -i a.mkv -vf scale=-2:480 a.480p.mkv], P[:resize].command(%w[a.mkv 480])
    assert_equal %w[ffmpeg -i a.mp4 -c:v libx264 -crf 28 -preset medium -c:a aac -b:a 128k a.compressed_crf28.mp4], P[:compress].command(%w[a.mp4])
    assert_equal %w[ffmpeg -i a.mp4 -c:v libx264 -crf 32 -preset slower -c:a aac -b:a 96k -vf scale=-2:480 a.small.mp4], P[:compress_small].command(%w[a.mp4])
    assert_equal %w[ffmpeg -i a.mp4 -ss 00:00:01 -vframes 1 a.thumb_00-00-01.jpg], P[:thumbnail].command(%w[a.mp4])
    assert_equal %w[ffmpeg -i a.mkv -map 0:s:0 a.subs_0.srt], P[:subs].command(%w[a.mkv])
    assert_equal %w[ffmpeg -i a.avi a.converted.webm], P[:convert].command(%w[a.avi webm])
  end

  def test_missing_arguments_fail_with_the_parameter_label
    error = assert_raises(Hiiro::Error) { P[:clip].command(%w[in.mp4 10]) }
    assert_equal "Missing required argument: duration (seconds or HH:MM:SS)", error.message
    error = assert_raises(Hiiro::Error) { P[:clip_precise].command(["in.mp4", " "]) }
    assert_equal "Missing required argument: start_time", error.message
    error = assert_raises(Hiiro::Error) { P[:to_mp4].command([]) }
    assert_equal "Missing required argument: input_file", error.message
  end
end
