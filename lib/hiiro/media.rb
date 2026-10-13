require 'json'
require 'open3'
require_relative 'error'

class Hiiro
  # FFmpeg recipes that share one shape: one input file, a few positional
  # parameters, fixed output arguments, and a default output named next to
  # the input's basename. Verbs with another shape (probes, two inputs,
  # pattern outputs, two-pass GIFs, derived filters) stay in bin/h-video.
  #
  #   clip_to = Hiiro::Media::PRESETS.fetch(:clip_to)
  #   clip_to.command(['in.mp4', '00:00:01', '3'])
  #   # => ["ffmpeg", "-i", "in.mp4", "-ss", "00:00:01", "-to", "3", "-c", "copy",
  #   #     "in.clip_00-00-01_to_3.mp4"]
  module Media
    # One positional parameter. A time parameter appears in output names
    # with ':' replaced by '-'.
    Param = Struct.new(:name, :label, :default, :time, keyword_init: true) do
      def required? = default.nil?
    end

    # args and suffix are templates over the parameter names (%{start});
    # ext nil keeps the input's extension, ext :param names the parameter
    # that supplies it (convert's format).
    Preset = Struct.new(:name, :params, :args, :suffix, :ext, keyword_init: true) do
      def values(argv)
        infile, *rest = argv
        Media.require_arg!(infile, 'input_file')
        values = params.each_with_index.to_h do |param, i|
          value = rest[i]
          value = param.default if value.nil?
          Media.require_arg!(value, param.label) if param.required?
          [param.name, value]
        end
        [infile, values, rest[params.length]]
      end

      def output_for(infile, values)
        named = values.to_h { |k, v| [k, params.find { |p| p.name == k }.time ? v.gsub(':', '-') : v] }
        extension = ext.is_a?(Symbol) ? values.fetch(ext) : ext
        Media.output_name(infile, format(suffix, named), extension)
      end

      def command(argv)
        infile, values, outfile = values(argv)
        outfile ||= output_for(infile, values)
        ['ffmpeg', '-i', infile, *args.map { |arg| format(arg, values) }, outfile]
      end
    end

    def self.param(name, label = name.to_s, default: nil, time: false)
      Param.new(name:, label:, default:, time:)
    end

    START = param(:start, 'start_time (e.g., 00:01:30 or 90)', time: true)

    PRESETS = [
      # resizing: scale to a height, width follows the aspect ratio rounded to even
      Preset.new(name: :resize, params: [param(:scale, default: '720')], args: ['-vf', 'scale=-2:%{scale}'], suffix: '%{scale}p'),
      Preset.new(name: :resize720, params: [], args: ['-vf', 'scale=-2:720'], suffix: '720p'),
      Preset.new(name: :resize1080, params: [], args: ['-vf', 'scale=-2:1080'], suffix: '1080p'),

      # containers and codec pairs
      Preset.new(name: :convert, params: [param(:format, 'format (e.g., mp4, mkv, avi, webm)')], args: [], suffix: 'converted', ext: :format),
      Preset.new(name: :to_mp4, params: [], args: %w[-c:v libx264 -c:a aac], suffix: 'converted', ext: 'mp4'),
      Preset.new(name: :to_webm, params: [], args: %w[-c:v libvpx-vp9 -c:a libopus], suffix: 'converted', ext: 'webm'),
      Preset.new(name: :to_mkv, params: [], args: %w[-c copy], suffix: 'converted', ext: 'mkv'),

      # audio extraction
      Preset.new(name: :audio, params: [], args: %w[-vn -acodec libmp3lame -q:a 2], suffix: 'audio', ext: 'mp3'),
      Preset.new(name: :audio_wav, params: [], args: %w[-vn], suffix: 'audio', ext: 'wav'),
      Preset.new(name: :audio_aac, params: [], args: %w[-vn -c:a aac -b:a 192k], suffix: 'audio', ext: 'aac'),
      Preset.new(name: :audio_flac, params: [], args: %w[-vn -c:a flac], suffix: 'audio', ext: 'flac'),

      # clips seek after -i; clip and clip_to copy streams, clip_precise re-encodes
      Preset.new(name: :clip, params: [START, param(:duration, 'duration (seconds or HH:MM:SS)')],
                 args: %w[-ss %{start} -t %{duration} -c copy], suffix: 'clip_%{start}'),
      Preset.new(name: :clip_to, params: [START, param(:end, 'end_time (e.g., 00:02:30 or 150)', time: true)],
                 args: %w[-ss %{start} -to %{end} -c copy], suffix: 'clip_%{start}_to_%{end}'),
      Preset.new(name: :clip_precise, params: [param(:start, 'start_time', time: true), param(:duration)],
                 args: %w[-ss %{start} -t %{duration}], suffix: 'clip_precise_%{start}'),

      Preset.new(name: :subs, params: [param(:stream, default: '0')], args: %w[-map 0:s:%{stream}], suffix: 'subs_%{stream}', ext: 'srt'),
      Preset.new(name: :thumbnail, params: [param(:timestamp, default: '00:00:01', time: true)],
                 args: %w[-ss %{timestamp} -vframes 1], suffix: 'thumb_%{timestamp}', ext: 'jpg'),

      Preset.new(name: :mute, params: [], args: %w[-c:v copy -an], suffix: 'muted'),
      Preset.new(name: :volume, params: [param(:level, 'level (e.g., 2.0 for 2x, 0.5 for half)')],
                 args: %w[-filter:a volume=%{level} -c:v copy], suffix: 'vol_%{level}'),

      # quality presets
      Preset.new(name: :compress, params: [param(:crf, default: '28')],
                 args: %w[-c:v libx264 -crf %{crf} -preset medium -c:a aac -b:a 128k], suffix: 'compressed_crf%{crf}'),
      Preset.new(name: :compress_small, params: [],
                 args: %w[-c:v libx264 -crf 32 -preset slower -c:a aac -b:a 96k -vf scale=-2:480], suffix: 'small'),

      Preset.new(name: :flip_h, params: [], args: %w[-vf hflip -c:a copy], suffix: 'flipped_h'),
      Preset.new(name: :flip_v, params: [], args: %w[-vf vflip -c:a copy], suffix: 'flipped_v'),
      Preset.new(name: :crop, params: [param(:crop, 'crop_params (w:h:x:y, e.g., 640:480:100:50)')], args: %w[-vf crop=%{crop}], suffix: 'cropped'),
      Preset.new(name: :fps, params: [param(:rate, 'rate (e.g., 30, 24, 60)')], args: %w[-filter:v fps=%{rate}], suffix: '%{rate}fps'),
      Preset.new(name: :strip_metadata, params: [], args: %w[-map_metadata -1 -c copy], suffix: 'clean'),
    ].to_h { |preset| [preset.name, preset] }.freeze

    # "dir/in.mp4", "clip_1" => "in.clip_1.mp4" (written to the current directory)
    def self.output_name(infile, suffix, new_ext = nil)
      ext = File.extname(infile)
      basename = File.basename(infile, ext)
      new_ext ||= ext
      new_ext = '.' + new_ext unless new_ext.start_with?('.')
      "#{basename}.#{suffix}#{new_ext}"
    end

    def self.require_arg!(value, label)
      raise Error, "Missing required argument: #{label}" if value.nil? || value.strip == ''
    end

    # Container duration in seconds, nil when ffprobe cannot read the file.
    def self.duration(path)
      out, _err, status = Open3.capture3('ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', path)
      return nil unless status.success?

      JSON.parse(out).dig('format', 'duration')&.to_f
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end
  end
end
