require 'digest'
require 'fileutils'
require 'json'

class Hiiro
  # The package's shared assets (commands in ~/bin, their supporting files, and
  # plugins) and the manifest of destinations hiiro wrote. A plan is read-only;
  # apply writes only the entries it is given and records ownership only for
  # writes that landed. A destination hiiro never wrote belongs to the user,
  # even when its bytes match the package, until the user adopts it.
  module Install
    # One row per kind of packaged file. `dest` maps the package-relative path
    # to a path under the row's destination root.
    SOURCES = [
      { asset: 'command', glob: 'bin/h-*', root: :bin,
        dest: ->(rel, prefix) { File.basename(rel).sub(/\Ah-/, "#{prefix}-") }, mode: ->(_) { 0o755 } },
      # Files a command loads relative to itself (require_relative 'lib/...').
      { asset: 'support', glob: 'bin/lib/**/*', root: :bin,
        dest: ->(rel, _) { rel.delete_prefix('bin/') }, mode: ->(path) { File.executable?(path) ? 0o755 : 0o644 } },
      { asset: 'plugin', glob: 'plugins/*.rb', root: :plugins,
        dest: ->(rel, _) { File.basename(rel) }, mode: ->(_) { 0o644 } }
    ].freeze

    # The default selection for --apply; collisions, user-modified files, and
    # obsolete files are never written unless named by --adopt / --retire.
    APPLY_KINDS = %w[missing updatable].freeze
    KINDS = %w[missing updatable user-modified collision obsolete unchanged].freeze

    def self.manifest_path = Config.config_dir('install-manifest.json')

    # What is on disk at a destination, never following a link.
    State = Struct.new(:type, :sha256, :mode, :link, keyword_init: true) do
      def self.missing = new(type: 'missing')

      def self.observe(path)
        stat = File.lstat(path)
        if stat.symlink? then new(type: 'link', link: File.readlink(path))
        elsif stat.file? then new(type: 'file', sha256: Digest::SHA256.file(path).hexdigest, mode: stat.mode & 0o7777)
        else new(type: 'other')
        end
      rescue Errno::ENOENT, Errno::ENOTDIR
        missing
      end

      def self.recorded(record) = new(type: 'file', sha256: record['sha256'], mode: record['mode'].to_i(8))

      def missing? = type == 'missing'
    end

    Package = Struct.new(:name, :version, :root, keyword_init: true) do
      def self.current = new(name: 'hiiro', version: Hiiro::VERSION, root: File.expand_path('../..', __dir__))

      def label = "#{name} #{version}"
      def identity = File.exist?(File.join(root, '.git')) ? "checkout #{root}" : "gem #{root}"
      def contains?(path) = File.expand_path(path).start_with?("#{root}/")

      # Package-relative paths of every shipped file, sorted.
      def sources
        SOURCES.flat_map { |row| Dir.glob(row[:glob], base: root).select { |rel| File.file?(File.join(root, rel)) } }.uniq.sort
      end

      # [{ asset:, source:, path:, destination:, desired: State }]
      def assets(prefix:, bin_dir:, plugin_dir:)
        roots = { bin: bin_dir, plugins: plugin_dir }
        SOURCES.flat_map do |row|
          Dir.glob(row[:glob], base: root).sort.filter_map do |rel|
            path = File.join(root, rel)
            next unless File.file?(path)

            { asset: row[:asset], source: rel, path:, destination: File.join(roots[row[:root]], row[:dest].call(rel, prefix)),
              desired: State.new(type: 'file', sha256: Digest::SHA256.file(path).hexdigest, mode: row[:mode].call(path)) }
          end
        end
      end
    end

    # { destination => { source, package, version, root, sha256, mode, owner, link? } }
    class Manifest
      attr_reader :path, :records

      def self.load(path = Install.manifest_path)
        records = File.exist?(path) ? JSON.parse(File.read(path)).fetch('assets') : {}
        new(path, records)
      rescue JSON::ParserError, KeyError => e
        raise Hiiro::Error, "Unreadable install manifest #{path}: #{e.message}"
      end

      def initialize(path, records = {})
        @path = path
        @records = records
      end

      def [](destination) = records[destination]

      def state_for(destination) = records[destination]&.then { |record| State.recorded(record) }

      def record(destination, fields) = records[destination] = fields
      def forget(destination) = records.delete(destination)

      def save
        FileUtils.mkdir_p(File.dirname(path))
        Install.atomic_write(path, JSON.pretty_generate({ 'assets' => records.sort.to_h }) + "\n", 0o644)
      end
    end

    Entry = Struct.new(:kind, :asset, :source, :path, :destination, :current, :desired, :record, keyword_init: true) do
      # An obsolete destination may be removed only while it holds the bytes hiiro wrote.
      def removable? = kind == 'obsolete' && (current.missing? || current == State.recorded(record))
      def matches?(name) = [destination, source, File.basename(destination), Install.display(destination)].include?(name)
    end

    Outcome = Struct.new(:entry, :action, :error, keyword_init: true) do
      def ok? = !%w[failed changed].include?(action)
      def recorded? = %w[installed updated adopted removed].include?(action)
    end

    class Plan
      attr_reader :package, :prefix, :bin_dir, :plugin_dir, :manifest, :entries

      def self.build(package: Package.current, prefix: 'h', bin_dir: File.join(Dir.home, 'bin'),
                     plugin_dir: Config.plugin_dir, manifest: Manifest.load)
        new(package:, prefix:, bin_dir:, plugin_dir:, manifest:)
      end

      def initialize(package:, prefix:, bin_dir:, plugin_dir:, manifest:)
        @package, @prefix, @bin_dir, @plugin_dir, @manifest = package, prefix, bin_dir, plugin_dir, manifest
        @entries = classify
      end

      def of(*kinds) = entries.select { |entry| kinds.include?(entry.kind) }

      def counts = Install::KINDS.to_h { |kind| [kind, of(kind).size] }

      # Selected entries; names (destination, basename, or source) narrow every kind.
      def select(apply: false, retire: false, adopt: false, names: [])
        picked = entries.select do |entry|
          (apply && APPLY_KINDS.include?(entry.kind)) || (retire && entry.removable?) || (adopt && entry.kind == 'collision')
        end
        names.empty? ? picked : picked.select { |entry| names.any? { |name| entry.matches?(name) } }
      end

      # Rechecks each destination before touching it; edits since planning
      # survive. When the manifest cannot be saved, nothing counts as owned.
      def apply(selected)
        outcomes = selected.map { |entry| apply_one(entry) }
        manifest.save if outcomes.any?(&:recorded?)
        outcomes
      rescue SystemCallError => e
        outcomes.map { |o| o.recorded? ? Outcome.new(entry: o.entry, action: 'failed', error: "manifest not saved: #{e.message}") : o }
      end

      private

      def classify
        assets = package.assets(prefix:, bin_dir:, plugin_dir:)
        shipped = package.sources
        current = assets.map do |asset|
          state = State.observe(asset[:destination])
          record = manifest[asset[:destination]]
          kind = if state.missing? then 'missing'
                 elsif record.nil? then 'collision'
                 elsif state == asset[:desired] then 'unchanged'
                 elsif state == manifest.state_for(asset[:destination]) then 'updatable'
                 else 'user-modified'
                 end
          Entry.new(kind:, **asset, current: state, record:)
        end
        obsolete = manifest.records.reject { |_, record| shipped.include?(record['source']) }.map do |destination, record|
          Entry.new(kind: 'obsolete', asset: record['asset'], source: record['source'], destination:,
                    current: State.observe(destination), record:)
        end
        (current + obsolete).sort_by { |entry| [Install::KINDS.index(entry.kind), entry.destination] }
      end

      def apply_one(entry)
        return Outcome.new(entry:, action: 'changed') unless State.observe(entry.destination) == entry.current

        case entry.kind
        when 'missing', 'updatable'
          FileUtils.mkdir_p(File.dirname(entry.destination))
          Install.atomic_write(entry.destination, File.binread(entry.path), entry.desired.mode)
          manifest.record(entry.destination, record_for(entry, entry.desired, 'installed'))
          Outcome.new(entry:, action: entry.kind == 'missing' ? 'installed' : 'updated')
        when 'collision'
          raise Hiiro::Error, "only a regular file can be adopted (found #{entry.current.type})" unless entry.current.type == 'file'

          manifest.record(entry.destination, record_for(entry, entry.current, 'adopted'))
          Outcome.new(entry:, action: 'adopted')
        when 'obsolete'
          raise Hiiro::Error, 'modified since hiiro wrote it' unless entry.removable?

          File.delete(entry.destination) unless entry.current.missing?
          manifest.forget(entry.destination)
          Outcome.new(entry:, action: 'removed')
        else
          raise Hiiro::Error, "#{entry.kind} is never applied"
        end
      rescue SystemCallError, IOError, Hiiro::Error => e
        Outcome.new(entry:, action: 'failed', error: e.message)
      end

      def record_for(entry, state, owner)
        { 'asset' => entry.asset, 'source' => entry.source, 'package' => package.name, 'version' => package.version,
          'root' => package.root, 'sha256' => state.sha256, 'mode' => format('%04o', state.mode), 'owner' => owner }
          .merge(File.symlink?(entry.path) ? { 'link' => File.readlink(entry.path) } : {})
      end
    end

    # Write beside the destination, then rename over it: a reader never sees a
    # partial file and a destination link is replaced, never written through.
    def self.atomic_write(path, bytes, mode)
      tmp = File.join(File.dirname(path), ".#{File.basename(path)}.hiiro-#{Process.pid}.tmp")
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, mode) { |file| file.write(bytes) }
      File.chmod(mode, tmp)
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    def self.display(path) = path.sub(/\A#{Regexp.escape(Dir.home)}(?=\/)/, '~')

    # Provenance of an installed command path: 'managed hiiro 0.1.393' while it
    # holds the bytes hiiro wrote, 'modified (managed hiiro 0.1.393)' after a
    # user edit, 'package hiiro 0.1.393' inside the running package, else 'user'.
    def self.origin(path, manifest: Manifest.load, package: Package.current)
      return 'user' unless path

      file = File.expand_path(path.sub(/:\d+\z/, ''))
      if (record = manifest[file])
        label = "managed #{record['package']} #{record['version']}"
        State.observe(file) == manifest.state_for(file) ? label : "modified (#{label})"
      elsif package.contains?(file)
        "package #{package.label}"
      else
        'user'
      end
    end

    NOTES = {
      'user-modified' => 'kept (changed since hiiro wrote it)',
      'collision' => 'kept (not written by hiiro; --adopt NAME to manage it)'
    }.freeze

    # `h setup [--apply] [--retire] [--adopt] [NAME...]`. Returns the exit status.
    def self.cli(args, prefix:, out: $stdout)
      opts = Hiiro::Options.parse(args) do
        flag(:apply, short: 'a', desc: 'Install missing assets and update unmodified managed ones')
        flag(:retire, short: 'r', desc: 'Remove obsolete managed assets that still hold the bytes hiiro wrote')
        flag(:adopt, desc: 'Take ownership of the named existing files as they are (requires NAME)')
      end
      if opts.help?
        out.puts "Usage: #{prefix} setup [--apply] [--retire] [--adopt NAME...] [NAME...]", opts.help_text
        return 0
      end
      if opts[:adopt] && opts.args.empty?
        out.puts 'ERROR: --adopt needs the NAME of each file to adopt'
        return 1
      end

      plan = Plan.build(prefix:)
      unless opts[:apply] || opts[:retire] || opts[:adopt]
        print_plan(plan, out)
        return 0
      end

      selected = plan.select(apply: opts[:apply], retire: opts[:retire], adopt: opts[:adopt], names: opts.args)
      print_plan(plan, out, except: selected)
      unknown = opts.args.reject { |name| plan.entries.any? { |entry| entry.matches?(name) } }
      out.puts
      unknown.each { |name| out.puts "  unknown   #{name}" }
      report(plan.apply(selected), out) && unknown.empty? ? 0 : 1
    rescue Hiiro::Error => e
      out.puts "ERROR: #{e.message}"
      1
    end

    # except: the entries being applied; their outcome lines follow instead.
    def self.print_plan(plan, out, except: nil)
      out.puts "Source: #{plan.package.label} (#{plan.package.identity})"
      out.puts "Commands: #{display(plan.bin_dir)}  Plugins: #{display(plan.plugin_dir)}  Manifest: #{display(plan.manifest.path)}"
      out.puts
      drift = plan.entries.reject { |entry| entry.kind == 'unchanged' || except&.include?(entry) }
      width = drift.map { |entry| display(entry.destination).length }.max.to_i
      source_width = drift.map { |entry| entry.source.length }.max.to_i
      drift.each do |entry|
        note = entry.kind == 'obsolete' ? (entry.removable? ? 'remove with --retire' : 'kept (changed since hiiro wrote it)') : NOTES[entry.kind]
        out.puts ["  #{entry.kind.ljust(13)}", display(entry.destination).ljust(width), entry.source.ljust(source_width), note].compact.join('  ').rstrip
      end
      out.puts if drift.any?
      out.puts plan.counts.reject { |_, n| n.zero? }.map { |kind, n| "#{n} #{kind}" }.join(', ').then { |s| s.empty? ? 'Nothing packaged' : s }
      pending = plan.of(*APPLY_KINDS).size
      out.puts "Run `#{plan.prefix} setup --apply` to write #{pending} asset#{'s' unless pending == 1}." if pending.positive? && !except
      warn_path(plan.bin_dir, out)
    end

    def self.report(outcomes, out)
      outcomes.each do |outcome|
        line = "  #{outcome.action.ljust(9)} #{display(outcome.entry.destination)}"
        line += case outcome.action
                when 'changed' then '  (changed since planning; left as is)'
                when 'failed' then "  (#{outcome.error})"
                else ''
                end
        out.puts line
      end
      failed = outcomes.reject(&:ok?)
      tally = outcomes.map(&:action).tally.map { |action, n| "#{n} #{action}" }.join(', ')
      out.puts "Applied: #{tally.empty? ? 'nothing selected' : tally}"
      failed.empty?
    end

    def self.warn_path(bin_dir, out)
      return if Bins.paths.include?(File.expand_path(bin_dir))

      out.puts
      out.puts "Warning: #{display(bin_dir)} is not in your PATH. Add to your shell config:"
      out.puts "  export PATH=\"$HOME/bin:$PATH\""
    end
  end
end
