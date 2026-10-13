require 'fileutils'
require 'pathname'
require 'securerandom'
require 'tmpdir'
require 'date'

class Hiiro
  # The `h context` manifest: current.bundle is one absolute path per line,
  # named bundles are saved copies, and dated directories hold captured files.
  #
  #   bundle = ContextBundle.new                     # $H_CONTEXT_DIR or ~/notes/ctx
  #   bundle.attach('/abs/file.png')                 # => Artifact::Attachment{ kind: :bundle, created: true }
  #   bundle.named_path('notes.md')                  # => ~/notes/ctx/2026-10-13/notes.md
  class ContextBundle
    attr_reader :root_dir, :bundles_dir, :named_bundles_dir, :current_bundle_path

    def self.default_root = ENV['H_CONTEXT_DIR'] || File.join(Dir.home, 'notes', 'ctx')

    # The one normalization for paths handed to a bundle or a task: '@' prefix
    # dropped, expanded, required to exist, symlinks resolved.
    def self.normalize_path(path)
      raw = path.to_s.sub(/\A@/, '')
      expanded = File.expand_path(raw)
      raise Error, "Path does not exist: #{raw}" unless File.exist?(expanded)

      File.realpath(expanded)
    end

    def initialize(root_dir: self.class.default_root)
      @root_dir = File.expand_path(root_dir)
      @bundles_dir = File.join(@root_dir, 'bundles')
      @named_bundles_dir = File.join(@bundles_dir, 'named')
      @current_bundle_path = File.join(@bundles_dir, 'current.bundle')
      ensure_dirs!
    end

    def ensure_dirs!
      FileUtils.mkdir_p(@named_bundles_dir)
      File.write(@current_bundle_path, '') unless File.exist?(@current_bundle_path)
    end

    def today_dir
      File.join(@root_dir, Date.today.strftime('%Y-%m-%d'))
    end

    # Destination of `h context save NAME` / `img NAME`: absolute as given,
    # else under today's directory.
    def named_path(name)
      raise Error, 'A file name is required.' if name.nil? || name.strip.empty?

      Pathname.new(name).absolute? ? File.expand_path(name) : File.expand_path(name, today_dir)
    end

    def temp_path(ext)
      File.join(Dir.tmpdir, "h-context-#{SecureRandom.uuid}.#{ext}")
    end

    def bundle_entries
      ensure_dirs!
      File.readlines(@current_bundle_path, chomp: true).map(&:strip).reject(&:empty?).uniq
    end

    def bundle_empty? = bundle_entries.empty?

    def write_bundle(entries)
      ensure_dirs!
      data = entries.uniq
      File.write(@current_bundle_path, data.empty? ? '' : data.join("\n") + "\n")
    end

    def reset_bundle!
      write_bundle([])
      @current_bundle_path
    end

    def append_paths(*paths)
      normalized = paths.flatten.map { |path| self.class.normalize_path(path) }
      write_bundle(bundle_entries + normalized)
      normalized
    end
    alias add_paths append_paths

    def attach(path)
      normalized = self.class.normalize_path(path)
      entries = bundle_entries
      created = !entries.include?(normalized)
      write_bundle(entries + [normalized]) if created
      Artifact::Attachment.new(kind: :bundle, identity: @current_bundle_path, path: normalized, created: created)
    end

    def copy_payload = bundle_entries.map { |path| "@#{path}" }.join("\n")

    def remove_entries(*targets)
      entries = bundle_entries
      to_remove = resolve_targets(entries, targets.flatten)
      write_bundle(entries.reject { |entry| to_remove.include?(entry) })
      to_remove
    end

    def save_named_bundle(name)
      raise Error, 'Bundle is empty.' if bundle_empty?

      dest = named_bundle_path(name)
      FileUtils.cp(@current_bundle_path, dest)
      dest
    end

    def load_named_bundle(name)
      src = named_bundle_path(name)
      raise Error, "Named bundle not found: #{src}" unless File.exist?(src)

      FileUtils.cp(src, @current_bundle_path)
      @current_bundle_path
    end

    def list_named_bundles
      Dir.glob(File.join(@named_bundles_dir, '*.bundle')).sort
    end

    def bundle_lines
      bundle_entries.each_with_index.map { |entry, idx| "#{idx + 1}. #{entry}" }
    end

    # Edits a copy of the manifest. Every line must name an existing path and
    # the manifest must be unchanged since the copy was made; otherwise the
    # manifest is left alone and the edited text is kept (InputFile#keep).
    # Returns :saved, :unchanged, or :cancelled (editor failed or emptied text).
    def edit(hiiro)
      original = File.read(@current_bundle_path)
      input = InputFile.new(hiiro: hiiro, type: :text, content: original, prefix: 'context-bundle-')
      document = input.edit.document
      return :cancelled unless document.editor_succeeded?
      return :unchanged unless document.changed?
      return :cancelled if document.empty?

      begin
        entries = document.data.map(&:strip).reject(&:empty?).map { |line| self.class.normalize_path(line) }
        raise Error, 'The bundle changed while it was being edited' unless File.read(@current_bundle_path) == original

        write_bundle(entries)
        :saved
      rescue Error, SystemCallError => e
        raise Error, "#{e.message}; bundle unchanged, edited text kept at #{input.keep}"
      end
    ensure
      input&.cleanup
    end

    private

    def named_bundle_path(name)
      sanitized = name.to_s.strip
      raise Error, 'Bundle name is required.' if sanitized.empty?

      sanitized += '.bundle' unless sanitized.end_with?('.bundle')
      File.join(@named_bundles_dir, sanitized)
    end

    def resolve_targets(entries, targets)
      targets.each_with_object([]) do |target, resolved|
        token = target.to_s.strip
        next if token.empty?

        if token.match?(/\A\d+\z/)
          entry = entries[token.to_i - 1]
          raise Error, "No bundle entry at index #{token}." unless entry && token.to_i.positive?

          resolved << entry
          next
        end

        cleaned = token.sub(/\A@/, '')
        expanded = File.expand_path(cleaned)
        matches = entries.select { |entry| entry == cleaned || entry == expanded || File.basename(entry) == cleaned }
        raise Error, "No bundle entry matches #{token.inspect}." if matches.empty?

        resolved.concat(matches)
      end.uniq
    end
  end
end
