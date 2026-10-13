require "test_helper"
require "open3"
require "tmpdir"

class CropTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BIN_DIR = %w[/opt/homebrew/bin /usr/local/bin].find { |d| File.executable?(File.join(d, "ffmpeg")) && File.executable?(File.join(d, "ffprobe")) }
  PYTHON = %w[/opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3].find { |p| File.executable?(p) }

  def setup
    skip "ffmpeg/ffprobe/python3 not installed" unless BIN_DIR && PYTHON
    @dir = Dir.mktmpdir("crop")
  end

  def teardown = @dir && FileUtils.rm_rf(@dir)

  def env = { "PATH" => "#{BIN_DIR}:/usr/bin:/bin" }

  # Black 640x360 frame with an amber (245,158,11) border drawn by ffmpeg.
  def amber(name, box)
    _, err, status = Open3.capture3(env, "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=640x360:rate=10", "-t", "1",
                                    "-vf", "drawbox=#{box}:color=0xF59E0B:t=4", "-c:v", "libx264", "-pix_fmt", "yuv420p", name, chdir: @dir)
    assert status.success?, err
  end

  def crop(*args) = Open3.capture3(env, PYTHON, "-I", File.join(ROOT, "bin/h-crop"), *args, chdir: @dir)

  def probe(file)
    out, = Open3.capture3(env, "ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0", file, chdir: @dir)
    out
  end

  def test_near_16_9_border_is_cropped_inside_to_even_dimensions_without_claiming_exact_16_9
    amber("amber.mp4", "x=101:y=51:w=327:h=187")
    out, err, status = crop("amber.mp4", "cropped.mp4")
    assert status.success?, err
    assert_equal <<~OUT, out
      Detected amber box: x=101, y=51, w=327, h=187
      Crop inside border: x=104, y=54, w=320, h=180
      16:9 validation: 1.77348 is within 1% of 16:9; crop 320x180 (dimensions made even, not exact 16:9)
    OUT
    assert_equal "h264,320,180\n", probe("cropped.mp4")

    _, err, status = crop("amber.mp4", "cropped.mp4")
    refute status.success?
    assert_equal "Refusing to overwrite existing output: cropped.mp4\n", err
  end

  def test_other_aspect_warns_and_still_crops_even
    amber("wide.mp4", "x=21:y=41:w=407:h=157")
    out, err, status = crop("wide.mp4", "wide.mkv", "--inset", "3")
    assert status.success?, err
    assert_equal "Detected amber box: x=21, y=41, w=407, h=157\nCrop inside border: x=24, y=44, w=400, h=150\n", out
    assert_includes err, "Warning: detected crop aspect is 2.65563, not within 1% of 16:9; cropping anyway.\n"
    assert_equal "h264,400,150\n", probe("wide.mkv")
  end

  def test_help_states_the_real_defaults
    out, _, status = crop("--help")
    assert status.success?
    assert_includes out, "RGB per-channel tolerance. Default: 60"
    assert_includes out, "Pixels to crop inside detected border. Default: 3"
  end
end
