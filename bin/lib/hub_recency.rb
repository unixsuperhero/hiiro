require 'open3'
require 'time'

class Hub
  # Newest-first listing of what changed under a hub link or group, from file
  # metadata only (no contents are read). `prs` is served by HubRecentPRs.
  #
  # Record: { 'name' =>, 'path' => hub path (or PR URL), 'timestamp' => UTC ISO8601,
  #           'basis' => 'created' | 'modified' | 'updated' }
  class Recency
    SKIP = %w[.git node_modules .cache .obsidian __pycache__ .venv venv dist build target
              .next vendor .DS_Store .localized].freeze
    PARTIAL_DOWNLOAD = %w[.part .crdownload .download .partial .tmp].freeze

    Rec = Struct.new(:name, :path, :time, :basis, :real) do
      def sort_key = [-(time.to_i * 1_000_000_000 + time.nsec), path]

      def to_h
        { 'name' => name, 'path' => path, 'timestamp' => time.utc.iso8601(3), 'basis' => basis }
      end
    end

    def initialize(hub)
      @hub = hub
    end

    # Returns an array of record hashes, newest first, at most `limit`.
    def recent(name, limit:, repo: nil)
      return prs(limit, repo) if name == 'prs'

      catalog = @hub.load_catalog
      name = @hub.resolve_name(catalog, name)
      recs = leaves(catalog, name).flat_map { |link_name| scan_leaf(link_name) }
      seen = {}
      recs.sort_by(&:sort_key).select { |r| seen[r.real] ? false : (seen[r.real] = true) }
          .first(limit).map(&:to_h)
    end

    private

    def prs(limit, repo)
      require_relative 'hub_recent_prs'
      records = HubRecentPRs.fetch(limit: limit, repo: repo)
      records.map { |r| r.slice('name', 'path', 'timestamp', 'basis') }
             .sort_by { |r| [-Time.parse(r['timestamp']).to_r, r['path']] }.first(limit)
    end

    # Registered link names that make up NAME (the link itself, or every link below a group).
    def leaves(catalog, name)
      names = catalog['links'].map { |l| l['name'] }
      return [name] if names.include?(name)

      names.select { |n| n.start_with?("#{name}/") }.sort
    end

    def scan_leaf(link_name)
      base = File.join(@hub.root, link_name)
      raise Error, "#{link_name}: path crosses a symlink or non-directory" if @hub.parent_state(base) == :blocked
      raise Error, "#{link_name}: target unavailable (run: h hub sync)" unless File.exist?(base)

      real = File.realpath(base)
      case link_name
      when 'downloads' then scan_downloads(base, real)
      when 'projects' then scan_projects(base, real)
      else scan_tree(base, real, link_name)
      end
    rescue SystemCallError => e
      raise Error, "#{link_name}: #{e.message}"
    end

    # --- generic: every file, recursively, by mtime ---------------------------

    def scan_tree(base, real, link_name)
      st = File.stat(base)
      return [Rec.new(File.basename(link_name), base, st.mtime, 'modified', real)] unless st.directory?

      recs = []
      each_entry(base) do |rel, es|
        next unless es.file?

        recs << Rec.new(File.basename(rel), File.join(base, rel), es.mtime, 'modified', File.join(real, rel))
      end
      recs
    end

    # --- downloads: direct complete items by creation time --------------------

    def scan_downloads(base, real)
      read_dir(base).filter_map do |child|
        next if child.start_with?('.') || SKIP.include?(child)
        next if PARTIAL_DOWNLOAD.include?(File.extname(child).downcase)

        st = lstat(File.join(base, child)) or next
        time, basis = birth_or_mtime(st)
        Rec.new(child, File.join(base, child), time, basis, File.join(real, child))
      end
    end

    def birth_or_mtime(st)
      [st.birthtime, 'created']
    rescue NotImplementedError, NoMethodError
      [st.mtime, 'modified']
    end

    # --- projects: one row per immediate directory, newest source change -------

    def scan_projects(base, real)
      read_dir(base).filter_map do |child|
        next if child.start_with?('.') || SKIP.include?(child)

        path = File.join(base, child)
        st = lstat(path)
        next unless st&.directory?

        time = File.exist?(File.join(path, '.git')) ? git_project_time(path, st) : walked_project_time(path, st)
        Rec.new(child, path, time, 'modified', File.join(real, child))
      end
    end

    def walked_project_time(path, st)
      newest = st.mtime
      each_entry(path) { |_rel, es| newest = es.mtime if !es.symlink? && es.mtime > newest }
      newest
    end

    # Tracked and untracked-but-not-ignored files. Each listed path counts its
    # own mtime (a regular file, never a symlink) and its containing directory's
    # mtime (an addition or deletion changed it). Ancestors are checked from the
    # project root down and never followed through a symlink; a vanished file or
    # an unsafe ancestor stops at the nearest surviving real directory.
    def git_project_time(path, st)
      out, err, status = Open3.capture3({ 'GIT_OPTIONAL_LOCKS' => '0' }, 'git', '-C', path,
                                        'ls-files', '--cached', '--others', '--exclude-standard', '-z')
      raise Error, "git ls-files failed in #{path}: #{err.strip}" unless status.success?

      newest = st.mtime
      dirs = { '' => st }
      out.split("\0").uniq.each do |rel|
        parts = rel.split('/')
        next if parts.any? { |part| SKIP.include?(part) }

        held = ''
        reached = true
        parts[0...-1].each do |part|
          held = held.empty? ? part : "#{held}/#{part}"
          dirs[held] = lstat(File.join(path, held)) unless dirs.key?(held)
          unless dirs[held]&.directory?
            held = File.dirname(held) == '.' ? '' : File.dirname(held)
            reached = false
            break
          end
        end
        dir_time = dirs[held].mtime
        newest = dir_time if dir_time > newest
        next unless reached

        leaf = lstat(File.join(path, rel))
        newest = leaf.mtime if leaf && !leaf.symlink? && leaf.mtime > newest
      end
      newest
    end

    # --- filesystem helpers ---------------------------------------------------

    # Yields [relative path, lstat] for everything under top; descends only real
    # directories (never symlinks) and never into SKIP names.
    def each_entry(top)
      stack = ['']
      until stack.empty?
        rel = stack.pop
        read_dir(rel.empty? ? top : File.join(top, rel)).each do |child|
          next if SKIP.include?(child)

          child_rel = rel.empty? ? child : File.join(rel, child)
          st = lstat(File.join(top, child_rel)) or next
          yield child_rel, st
          stack << child_rel if st.directory?
        end
      end
    end

    def read_dir(dir)
      Dir.children(dir)
    rescue Errno::ENOENT
      []
    end

    def lstat(path)
      File.lstat(path)
    rescue Errno::ENOENT
      nil
    end
  end
end
