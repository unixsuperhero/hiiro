require 'fileutils'
require 'json'
require 'time'
require_relative 'error'

class Hiiro
  # Records visible app-window regions of one avfoundation screen into one
  # video file per window, from a single ffmpeg process. The recording is
  # detached; a state file lets stop and status find it later.
  #
  #   plan = Hiiro::ScreenCapture::Plan.new(
  #     apps: ['Ghostty'], rects: [[0, 25, 1200, 800]], out_dir: '/m', session_name: 'yt.20261013-120000')
  #   plan.outputs  # => ["/m/yt.20261013-120000-ghostty.mov", "/m/yt.20261013-120000-audio.wav"]
  #   plan.command  # => ["ffmpeg", "-hide_banner", ..., "-filter_complex", "[0:v]crop=1200:800:0:25,...[v0]", ...]
  module ScreenCapture
    AUDIO_MODES = %w[separate first all none].freeze
    VIDEO_FORMATS = %w[mp4 mkv mov].freeze

    def self.state_dir = File.expand_path('~/.local/state/h-screencap')
    def self.state_file = File.join(state_dir, 'recording.json')

    def self.out_dir(profile = Profile.load)
      profile.section('screencap', 'out_dir' => '~/Movies/h-screencap').path('out_dir')
    end

    # Personal app recipes, e.g. { "codehiiro" => { "open" => "release/CodeHiiro.app", "process" => "CodeHiiro" } }
    def self.app_recipe(name, profile = Profile.load)
      recipes = profile.section('screencap', 'apps' => {})['apps'] || {}
      recipes[name]
    end

    # Window bounds scaled to capture pixels; yuv420p needs even width and height.
    def self.normalize_rect(bounds, scale)
      x, y, w, h = bounds.map { |value| (value * scale).round }
      w -= 1 if w.odd?
      h -= 1 if h.odd?
      [x, y, w, h]
    end

    def self.slug(value)
      value.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-+\z/, '')
    end

    def self.audio_mode(audio, mode)
      return 'none' if audio == 'none'
      return mode if AUDIO_MODES.include?(mode)

      raise Error, "invalid --audio-mode=#{mode.inspect}; expected separate, first, all, or none"
    end

    def self.video_format(format)
      normalized = format.downcase
      return normalized if VIDEO_FORMATS.include?(normalized)

      raise Error, "invalid --video-format=#{format.inspect}; expected mp4, mkv, or mov"
    end

    Plan = Struct.new(:apps, :rects, :out_dir, :session_name, :screen, :audio, :audio_mode, :audio_bitrate,
                      :video_format, :framerate, keyword_init: true) do
      def initialize(screen: '1', audio: '0', audio_mode: 'separate', audio_bitrate: '320k', video_format: 'mov', framerate: '30', **rest)
        super
      end

      def video_files = apps.map { |app| File.join(out_dir, "#{session_name}-#{ScreenCapture.slug(app)}.#{video_format}") }
      def audio_file = File.join(out_dir, "#{session_name}-audio.wav")
      def outputs = audio_mode == 'separate' ? [*video_files, audio_file] : video_files
      def log_file = File.join(out_dir, "#{session_name}.ffmpeg.log")

      def filter_graph
        rects.each_with_index.map do |(x, y, w, h), index|
          "[0:v]crop=#{w}:#{h}:#{x}:#{y},setpts=PTS-STARTPTS,fps=#{framerate},setsar=1[v#{index}]"
        end.join(';')
      end

      def command
        cmd = [
          'ffmpeg', '-hide_banner', '-loglevel', 'warning',
          '-f', 'avfoundation', '-capture_cursor', '1', '-capture_mouse_clicks', '1',
          '-framerate', framerate,
          '-i', "#{screen}:#{audio_mode == 'none' ? 'none' : audio}",
          '-filter_complex', filter_graph
        ]
        video_files.each_with_index do |file, index|
          cmd.concat(['-map', "[v#{index}]", '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p'])
          cmd.concat(['-movflags', '+faststart']) if %w[mp4 mov].include?(video_format)
          cmd.concat(['-map', '0:a?', '-c:a', 'aac', '-b:a', audio_bitrate]) if audio_mode == 'all' || (audio_mode == 'first' && index.zero?)
          cmd << file
        end
        cmd.concat(['-map', '0:a?', '-vn', '-c:a', 'pcm_s16le', audio_file]) if audio_mode == 'separate'
        cmd
      end
    end

    # A detached process group fed from a FIFO, so stop can send ffmpeg's
    # own quit key before falling back to signals.
    module Process
      module_function

      def alive?(pid)
        stat = `ps -o stat= -p #{pid.to_i} 2>/dev/null`.strip
        return false if stat.empty? || stat.include?('Z')

        ::Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def wait_until_exited(pid, timeout_seconds)
        deadline = Time.now + timeout_seconds
        while Time.now < deadline
          return true unless alive?(pid)

          sleep 0.25
        end
        !alive?(pid)
      end

      def send_quit(control_file)
        return false unless control_file && File.exist?(control_file)

        File.open(control_file, 'w') { |file| file.write("q\n") }
        true
      rescue Errno::ENXIO, Errno::EPIPE, Errno::ENOENT
        false
      end

      def signal_group(signal, pid)
        ::Process.kill(signal, -pid.to_i)
      rescue Errno::ESRCH
        nil
      end

      # INT, then TERM, then KILL to the whole group, each after a wait.
      def terminate_group(pid, graceful_timeout: 30, term_timeout: 2)
        signal_group('INT', pid)
        return :int if wait_until_exited(pid, graceful_timeout)

        signal_group('TERM', pid)
        return :term if wait_until_exited(pid, term_timeout)

        signal_group('KILL', pid)
        :kill
      end

      # :quit when ffmpeg read q from the FIFO and exited in time; otherwise
      # the signal that ended the group.
      def stop(pid, control_file, quit_timeout: 30, graceful_timeout: 30, term_timeout: 2)
        return :quit if send_quit(control_file) && wait_until_exited(pid, quit_timeout)

        terminate_group(pid, graceful_timeout:, term_timeout:)
      end

      def spawn(command, control_file:, log_file:)
        FileUtils.rm_f(control_file)
        raise Error, "failed to create ffmpeg control pipe at #{control_file}" unless system('mkfifo', control_file)

        log = File.open(log_file, 'a')
        # RDWR keeps the FIFO open without a writer, so ffmpeg's stdin never sees EOF.
        control_io = File.open(control_file, File::RDWR | File::NONBLOCK)
        pid = ::Process.spawn(*command, in: control_io, out: log, err: log, pgroup: true)
        control_io.close
        log.close
        pid
      end
    end
  end
end
