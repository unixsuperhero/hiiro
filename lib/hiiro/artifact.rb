require 'fileutils'
require 'securerandom'

class Hiiro
  # One captured file: clipboard or argument content written once to the path
  # the calling command chose, then optionally attached to a context bundle or
  # a task. Destination policy (inbox, named note, bundle directory) belongs to
  # the command; this class only reads, writes, and attaches.
  #
  #   outcome = Artifact.capture(:image_first) { |payload| candidates_for(payload.extension) }
  #   outcome.status    # :ok | :empty_clipboard | :missing_image_tool | :adapter_failed | :write_failed
  #   outcome.artifact  # Captured{ path: '/abs/x.png', content_type: 'image/png', bytes: 1234, source: :clipboard_image }
  class Artifact
    Captured = Struct.new(:path, :content_type, :bytes, :source, keyword_init: true)

    # existing is the path that refused a write because it already exists.
    Outcome = Struct.new(:status, :artifact, :detail, :existing, keyword_init: true) do
      def ok? = status == :ok
    end

    # kind :bundle | :task; identity is the bundle file or task name; created is
    # false when the association already existed.
    Attachment = Struct.new(:kind, :identity, :path, :created, keyword_init: true)

    MODES = %i[text_arg text image image_first].freeze

    # mode :text_arg (text: given), :text, :image, or :image_first (image when
    # the clipboard holds one, else its text). The block receives the payload
    # and returns one path or an enumerable of candidate paths; with
    # overwrite: false the first path that does not exist yet is created.
    def self.capture(mode, text: nil, overwrite: false, clipboard: Clipboard, &destination)
      raise ArgumentError, "Unknown capture mode #{mode.inspect}" unless MODES.include?(mode)

      payload = read(mode, text: text, clipboard: clipboard)
      return Outcome.new(status: payload.status, detail: payload.detail) unless payload.ok?

      write(payload, destination.call(payload), overwrite: overwrite)
    end

    def self.read(mode, text:, clipboard:)
      case mode
      when :text_arg
        Clipboard::Payload.new(source: :text_arg, content_type: 'text/plain', bytes: text.to_s.b)
      when :text then clipboard.text
      when :image then clipboard.image
      when :image_first
        image = clipboard.image
        image.ok? || image.status == :adapter_failed ? image : clipboard.text
      end
    end

    def self.write(payload, candidates, overwrite: false)
      paths = candidates.is_a?(String) ? [candidates] : candidates
      existing = nil
      paths.each do |candidate|
        path = File.expand_path(candidate)
        begin
          FileUtils.mkdir_p(File.dirname(path))
          begin
            overwrite ? replace(path, payload.bytes) : create(path, payload.bytes)
          rescue Errno::EEXIST
            existing = path
            next
          end
        rescue SystemCallError, IOError => e
          return Outcome.new(status: :write_failed, detail: "Could not write #{path}: #{e.message}")
        end
        artifact = Captured.new(path: path, content_type: payload.content_type, bytes: File.size(path), source: payload.source)
        return Outcome.new(status: :ok, artifact: artifact)
      end
      return Outcome.new(status: :write_failed, detail: 'No destination path') unless existing

      Outcome.new(status: :write_failed, detail: "#{existing} already exists", existing: existing)
    end

    def self.create(path, bytes)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o644) do |file|
        file.write(bytes)
      rescue StandardError
        File.unlink(path)
        raise
      end
    end

    def self.replace(path, bytes)
      raise Errno::EISDIR, path if File.directory?(path)

      staging = File.join(File.dirname(path), ".#{File.basename(path)}.#{SecureRandom.hex(4)}.tmp")
      File.binwrite(staging, bytes)
      File.rename(staging, path)
    ensure
      File.unlink(staging) if staging && File.exist?(staging)
    end

    # Candidate inbox names: base.ext, base-2.ext, ... base-1000.ext. The list
    # is finite so a write error mistaken for a taken name can never spin
    # (an unbounded list once kept an orphaned h save at 80% CPU for hours).
    NUMBERED_LIMIT = 1000

    def self.numbered(dir, base, ext)
      Enumerator.new do |yielder|
        yielder << File.join(dir, "#{base}.#{ext}")
        (2..NUMBERED_LIMIT).each { |n| yielder << File.join(dir, "#{base}-#{n}.#{ext}") }
      end
    end

    def self.attach_to_task(task, path, label: nil)
      resource, created = TaskResource.attach!(task, kind: 'file', target: ContextBundle.normalize_path(path), label: label)
      Attachment.new(kind: :task, identity: task.name, path: resource.target, created: created)
    end

    # Exact name or unique prefix; '.' is the task the current directory,
    # Herdr pane, or pin names. Ambiguity and absence are errors, never a pick.
    def self.task_for(reference, cwd: Dir.pwd)
      return CurrentTask.new(cwd: cwd).resolve! if reference == '.'

      CurrentTask.new(task: reference, cwd: cwd).resolve!
    end

    # Destinations are resolved before the clipboard is read; #finish prints the
    # artifact path on stdout and each attachment on stderr. Exit status: 0 all
    # done, 1 nothing captured, 2 captured but an attachment failed.
    class Handoff
      attr_reader :attachments, :failures

      def initialize(bundle: nil, task: nil, label: nil, out: $stdout, err: $stderr)
        @bundle = bundle
        @task = task
        @label = label
        @out = out
        @err = err
        @attachments = []
        @failures = []
      end

      def finish(outcome)
        unless outcome.ok?
          @err.puts outcome.detail
          return 1
        end
        path = outcome.artifact.path
        @out.puts path
        attach(:bundle, @bundle&.current_bundle_path, path) { @bundle.attach(path) } if @bundle
        attach(:task, @task&.name, path) { Artifact.attach_to_task(@task, path, label: @label) } if @task
        @failures.empty? ? 0 : 2
      end

      private

      def attach(kind, identity, path)
        attachment = yield
        @attachments << attachment
        @err.puts "attached to #{kind} #{identity}#{' (already attached)' unless attachment.created}"
      rescue StandardError => e
        @failures << [kind, identity, e.message]
        @err.puts "attach to #{kind} #{identity} failed: #{e.message}; artifact kept at #{path}"
      end
    end
  end
end
