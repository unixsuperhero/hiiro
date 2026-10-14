require 'json'
require 'sequel'
require 'time'
require 'date'
require 'digest'
require 'yaml'
require 'fileutils'

class Hiiro
  module DB
    MODELS = []
    DB_FILE = Hiiro::Config.path('hiiro.db')
    PARSER_VERSION = 1
    OWNED_STORES = {
      todos: ['todo.yml', :todos, 'TodoItem', 'id'],
      links: ['links.yml', :registry, 'RegistryEntry', 'link/url'],
      branches: ['branches.yml', :branches, 'Branch', 'name/worktree'],
      prs: ['prs.yml', :prs, 'PinnedPr', 'repo/number'],
      pinned_prs: ['pinned_prs.yml or sqlite:pinned_prs (retained legacy table)', :prs, 'PinnedPr', 'repo/number'],
      tasks: ['tasks/tasks.yml + tasks/task_*.yml', :tasks, 'TaskRecord', 'name'],
      assignments: ['tasks/assignments.yml', :assignments, 'Assignment', 'worktree'],
      apps: ['apps.yml', :apps, 'AppRecord', 'name'],
      projects: ['projects.yml', :registry, 'RegistryEntry', 'project/name'],
      pane_homes: ['pane_homes.yml', :pane_homes, 'PaneHome', 'name'],
      pins: ['pins/<command>[.yml]', :registry, 'RegistryEntry', '<command>/key'],
      sounds: ['sounds.yml', :registry, 'RegistryEntry', 'sound/name'],
      reminders: ['reminders.yml', :reminders, 'Reminder', 'id or source ordinal'],
      tags: ['tags.yml', :tags, 'Tag', 'name/type/record ID']
    }.freeze
    NATURAL_KEYS = {
      branches: %i[name worktree], prs: %i[repo number], tasks: %i[name],
      assignments: %i[worktree], apps: %i[name], pane_homes: %i[name],
      tags: %i[name taggable_type taggable_id],
      task_resources: %i[task_id kind target], registry: %i[resource_type name]
    }.freeze
    TAG_OWNERS = {'branch' => [:branches, 'Branch', :name], 'task' => [:tasks, 'Task', :name],
                  'pr' => [:prs, 'PinnedPr', :id], 'pinned_pr' => [:prs, 'PinnedPr', :id],
                  'link' => [:registry, 'RegistryEntry', :id, {resource_type: 'link'}], 'task_record' => [:tasks, 'TaskRecord', :id],
                  'registry_entry' => [:registry, 'RegistryEntry', :id]}.freeze
    class ImportError < StandardError; end

    class << self
      # A model registered after setup! (one defined by a bin) gets its table at once,
      # so such a model registers at the end of its class body, after create_table!.
      def register(cls)
        MODELS << cls
        install(connection, cls) if @setup_done
      end

      def connection
        @connection ||= begin
          FileUtils.mkdir_p(File.dirname(DB_FILE)) unless ENV.key?('HIIRO_TEST_DB')
          db = Sequel.connect(ENV.fetch('HIIRO_TEST_DB', "sqlite://#{DB_FILE}"), logger: nil)
          db.run('PRAGMA journal_mode=WAL')
          Sequel::Model.db = db
          db
        end
      end
      alias db connection

      def setup!
        return if @setup_done
        conn = connection
        conn.transaction do
          conn.create_table?(:schema_migrations) do
            String :name, primary_key: true
            String :ran_at
          end
          MODELS.each { |cls| install(conn, cls) }
          ensure_todo_allocator!
          unless conn[:schema_migrations].where(name: 'registry_tables_v1').count.positive?
            import_legacy_tables!
            conn[:schema_migrations].insert(name: 'registry_tables_v1', ran_at: Time.now.iso8601)
          end
          # MCPRegistry (lib/hiiro/mcp/registry.rb) owns these rows; the schema is
          # here so export and restore know the table before h mcp first runs.
          conn.create_table?(:mcps) do
            String :name, text: true, primary_key: true, null: false
            String :record_json, text: true, null: false
            String :created_at, text: true, null: false
            String :updated_at, text: true, null: false
          end
          conn.create_table?(:migration_sources) do
            primary_key :id
            String :store, null: false
            String :logical_source_key, null: false, unique: true
            String :source_path, null: false
            String :variant, null: false
            String :source_sha256, null: false
            Integer :parser_version, null: false
            String :semantic_sha256, null: false
            String :verified_at, null: false
          end
          conn.create_table?(:migration_rows) do
            primary_key :id
            foreign_key :source_id, :migration_sources, null: false
            String :row_locator, null: false
            String :target_table, null: false
            String :target_id, null: false
            String :imported_semantic_sha256, null: false
            unique [:source_id, :row_locator, :target_table]
          end
        end
        @setup_done = true
      end

      def install(conn, cls)
        cls.create_table!(conn)
        cls.migrate!(conn) if cls.respond_to?(:migrate!)
        [cls, cls.superclass].each do |klass|
          %i[@db_schema @columns @setter_methods].each { |cache| klass.instance_variable_set(cache, nil) }
        end
        cls.send(:get_db_schema)
      end

      def migrated?
        setup!
        connection[:schema_migrations].where(name: 'owned_yaml_import_v1').count.positive?
      end

      # Registry name for a link: shorthand, else description, else the url.
      # Falls back to the url when another link already holds that name.
      def link_name(url, shorthand, description)
        preferred = [shorthand, description, url].map(&:to_s).find { |s| !s.empty? }
        holder = connection[:registry].where(resource_type: 'link', name: preferred).get(:value)
        holder.nil? || holder == url ? preferred : url
      end

      # Rows of the retired `pins`, `links`, and `projects` tables (written by
      # hiiro before 0.1.392) become registry entries. The tables are left in
      # place; every row is skipped when its entry already exists, so this is
      # safe to repeat. Legacy YAML files are explicit `h db migrate` inputs.
      def import_legacy_tables!
        import_legacy_pins_table
        import_legacy_links_table
        import_legacy_projects_table
      end

      def owned_store_manifest
        OWNED_STORES.map do |store, (source, table, owner, identity)|
          {store: store.to_s, source: source, table: table.to_s, owner: owner, identity: identity,
           dependencies: store == :tags ? %w[tasks links branches prs pinned_prs] : [],
           recovery: 'Sources retained byte-identical; .bak requires explicit selection', parser_version: PARSER_VERSION}
        end + {task_resources: 'TaskResource', registry: 'RegistryEntry', check_runs: 'CheckRun', captures: 'Capture',
           pr_monitor_checkpoints: 'PrMonitorCheckpoint', job_claims: 'JobClaim', job_outcomes: 'JobOutcome',
           schedule_checkpoints: 'ScheduleCheckpoint', picker_exclusions: 'PickerExclusion'}.map do |table, owner|
          {store: table.to_s, source: 'database only; canonical export', table: table.to_s, owner: owner,
           identity: 'stable row ID', dependencies: [], recovery: 'Full typed export; no legacy YAML authority', parser_version: PARSER_VERSION}
        end + [{store: 'mcps', source: 'h mcp; legacy ~/.local/share/hiiro/mcp/*.json imported once and retained', table: 'mcps',
                owner: 'MCPRegistry', identity: 'name', dependencies: [], recovery: 'Full typed export; legacy JSON is not read again',
                parser_version: PARSER_VERSION}]
      end

      def migration_plan(only: nil, sources: nil, base: Hiiro::Config::BASE_DIR)
        setup!
        stores = only ? Array(only).map(&:to_sym) : OWNED_STORES.keys
        unknown = stores - OWNED_STORES.keys
        raise ImportError, "Unknown stores: #{unknown.join(', ')}" unless unknown.empty?
        stores |= %i[tasks links branches prs pinned_prs] if stores.include?(:tags)
        available = discover_sources(base)
        inventory = available.map(&:dup)
        if sources
          selected = Array(sources).map { |path| path == 'sqlite:pinned_prs' ? path : File.expand_path(path, base) }
          missing = selected - available.map { |entry| entry[:path] }
          raise ImportError, "Not owned migration sources: #{missing.join(', ')}" unless missing.empty?
          available.select! { |entry| selected.include?(entry[:path]) }
        else
          available.reject! { |entry| entry[:variant] == 'bak' }
        end
        entries = available.select { |entry| stores.include?(entry[:store]) }.map do |entry|
          bytes = source_bytes(entry)
          entry.merge(bytes: bytes, checksum: Digest::SHA256.hexdigest(bytes))
        end
        plan = {manifest: owned_store_manifest, stores: stores, available_sources: inventory, entries: entries, errors: [], report: []}
        begin
          prepare_rows!(entries)
          connection.transaction(rollback: :always, mode: :immediate) { apply_entries!(plan) }
        rescue ImportError, Sequel::Error, Psych::Exception, ::JSON::ParserError, ::JSON::GeneratorError, ArgumentError => error
          plan[:errors] << error.message
        end
        plan[:report].each { |entry| entry[:status] = plan[:errors].empty? ? 'ready' : 'rolled-back' if entry[:status] == 'verified' }
        plan
      end

      def migrate!(plan: nil, **options)
        plan ||= migration_plan(**options)
        raise ImportError, plan[:errors].join("\n") unless plan[:errors].empty?
        report = []
        checks = []
        connection.transaction(mode: :immediate) do
          plan[:entries].each do |entry|
            unless source_checksum(entry) == entry[:checksum]
              raise ImportError, "Source changed after plan: #{entry[:path]}"
            end
          end
          apply_entries!(plan.merge(report: report))
          report.each do |entry|
            logical = plan[:entries].find { |source| source[:path] == entry[:source] }[:logical]
            source = connection[:migration_sources].where(logical_source_key: logical).first
            checks << [:migration_sources, {id: source[:id]}, source]
            connection[:migration_rows].where(source_id: source[:id]).each do |mapping|
              checks << [:migration_rows, {id: mapping[:id]}, mapping]
              table = mapping[:target_table].to_sym
              identity = {id: mapping[:target_id]}
              checks << [table, identity, connection[table].where(identity).first]
            end
          end
          connection[:schema_migrations].where(name: 'owned_yaml_import_v1').delete if report.any? { |entry| entry[:status] == 'verified' }
        end
        begin
          verify_committed!(checks)
        rescue ImportError, Sequel::Error, SystemCallError => error
          raise ImportError, "Committed but persistence verification failed: #{error.message}; sources and accepted ledger retained, completion not recorded"
        end
        connection[:schema_migrations].insert_conflict.insert(name: 'owned_yaml_import_v1', ran_at: Time.now.iso8601)
        report
      end

      def export!(path)
        setup!
        payload = connection.transaction do
          tables = export_tables.to_h { |table| [table.to_s, connection[table].order(*connection.schema(table).map(&:first)).all] }
          tables['schema_migrations']&.reject! { |row| row[:name] == 'registry_tables_v1' }
          pr_columns = %i[prs pinned_prs].select { |table| connection.table_exists?(table) }.to_h do |table|
            [table.to_s, connection.schema(table).map { |name, info| {name: name.to_s, type: info[:type].to_s, null: info[:allow_null]} }]
          end
          {format: 'hiiro-owned-records', version: 1, tables: tables, sequences: sequences, pr_columns: pr_columns,
           recovery_policy: 'Merge only absent or identical IDs/identities; conflicting later writes abort. No deletion or overwrite.'}
        end
        document = {payload: payload, sha256: semantic_digest(payload)}
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(::JSON.pretty_generate(document))
          file.flush
          file.fsync
        end
        path
      end

      def restore!(path)
        setup!
        document = ::JSON.parse(File.binread(path))
        payload = document.fetch('payload')
        raise ImportError, 'Export checksum mismatch' unless semantic_digest(payload) == document['sha256']
        raise ImportError, 'Unsupported recovery format' unless payload['format'] == 'hiiro-owned-records' && payload['version'] == 1
        tables = payload.fetch('tables')
        unknown = tables.keys - (export_tables.map(&:to_s) + ['pinned_prs'])
        raise ImportError, "Unknown recovery tables: #{unknown.join(', ')}" unless unknown.empty?
        report = []
        connection.transaction(mode: :immediate) do
          restore_pr_columns!(payload.fetch('pr_columns'))
          export_tables.each do |table|
            next unless tables.key?(table.to_s)
            require_array(tables[table.to_s], table.to_s).each_with_index do |raw, index|
              row = require_hash(raw, "#{table}/#{index}").transform_keys(&:to_sym)
              validate_row!(table, row)
              id = row.fetch(:id) { row.fetch(:name) }
              key = %i[schema_migrations mcps].include?(table) ? :name : :id
              existing = connection[table].where(key => id).first
              if existing
                raise ImportError, "Recovery conflicts with later write: #{table}/#{id}" unless existing == row
              else
                conflict = natural_match(table, row)
                raise ImportError, "Recovery identity collision: #{table}/#{id}" if conflict
                connection[table].insert(row)
              end
              verify_row!(table, row, key => id)
              report << {table: table.to_s, id: id, status: existing ? 'identical' : 'restored'}
            end
          end
          validate_relations!
          require_array(payload.fetch('sequences'), 'sequences').each do |sequence|
            raise ImportError, 'Invalid allocator record' unless sequence.keys.sort == %w[name seq] && sequence['seq'].is_a?(Integer)
            raise ImportError, 'Unknown allocator table' unless export_tables.map(&:to_s).include?(sequence['name'])
            raise_sequence!(sequence['name'], sequence['seq'])
          end
        end
        report
      rescue KeyError => error
        raise ImportError, "Invalid recovery document: #{error.message}"
      end

      private

      def restore_pr_columns!(tables)
        types = {'string' => String, 'integer' => Integer, 'boolean' => TrueClass, 'float' => Float}
        require_hash(tables, 'pr_columns').each do |name, columns|
          raise ImportError, 'Unknown PR recovery schema' unless %w[prs pinned_prs].include?(name)
          definitions = require_array(columns, name).map do |column|
            column = require_hash(column, name)
            type = types[column['type']] || raise(ImportError, "Unsupported PR column type: #{column['type']}")
            raise ImportError, 'Invalid PR column name' unless column['name'].is_a?(String) && column['name'].match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            [column['name'].to_sym, type, column['null']]
          end
          table = name.to_sym
          unless connection.table_exists?(table)
            connection.create_table(table) do
              definitions.each { |column, type, nullable| column(column, type, null: nullable, primary_key: column == :id) }
            end
          end
          existing = connection.schema(table).map(&:first)
          definitions.each do |column, type, nullable|
            next if existing.include?(column)
            connection.alter_table(table) { add_column(column, type, null: nullable) }
          end
        end
      end

      def source_bytes(entry)
        if entry[:variant] == 'legacy-sql'
          ::JSON.generate(connection[:pinned_prs].order(:id).all)
        else
          File.binread(entry[:path])
        end
      end

      def source_checksum(entry)
        Digest::SHA256.hexdigest(source_bytes(entry))
      rescue Errno::ENOENT
        nil
      end

      def verify_committed!(checks)
        return if checks.empty? || connection.opts[:database] == ':memory:'
        fresh = Sequel.connect(connection.opts)
        checks.each do |table, identity, expected|
          unless fresh[table].where(identity).first == expected
            raise ImportError, "Committed but persistence verification failed: #{table}/#{identity}; sources retained"
          end
        end
      ensure
        fresh&.disconnect
      end

      def export_tables
        %i[tasks prs registry todos branches assignments apps pane_homes reminders tags task_resources check_runs captures
           pr_monitor_checkpoints job_claims job_outcomes schedule_checkpoints picker_exclusions mcps schema_migrations migration_sources migration_rows pinned_prs].select { |table| connection.table_exists?(table) }
      end

      def sequences
        return [] unless connection.table_exists?(:sqlite_sequence)
        connection[:sqlite_sequence].where(name: export_tables.map(&:to_s)).order(:name).all
      end

      def raise_sequence!(table, value)
        raise ImportError, "No SQLite allocator for #{table}" unless connection.table_exists?(:sqlite_sequence)
        row = connection[:sqlite_sequence].where(name: table.to_s).first
        if row
          connection[:sqlite_sequence].where(name: table.to_s).update(seq: value) if value > row[:seq]
        else
          connection[:sqlite_sequence].insert(name: table.to_s, seq: value)
        end
      end

      def ensure_todo_allocator!
        sql = connection[:sqlite_master].where(type: 'table', name: 'todos').get(:sql)
        return unless sql && !sql.include?('AUTOINCREMENT')
        indexes = connection[:sqlite_master].where(type: 'index', tbl_name: 'todos').exclude(sql: nil).select_map(:sql)
        replacement = sql.sub(/\A(CREATE TABLE\s+)(?:`todos`|"todos"|todos)/i, '\1"hiiro_todos_allocator"')
        replacement = replacement.sub(/(\bid\b["`]?\s+integer\s+(?:NOT NULL\s+)?PRIMARY KEY)/i, '\1 AUTOINCREMENT')
        raise ImportError, 'Cannot safely migrate todos allocator schema' unless replacement.include?('AUTOINCREMENT')
        connection.run(replacement)
        columns = connection.schema(:todos).map(&:first)
        connection[:hiiro_todos_allocator].insert(columns, connection[:todos].select(*columns))
        connection.drop_table(:todos)
        connection.rename_table(:hiiro_todos_allocator, :todos)
        indexes.each { |index| connection.run(index) }
      end

      def discover_sources(base)
        paths = OWNED_STORES.flat_map do |store, (source, *)|
          names = case store
          when :tasks
            ['tasks/tasks.yml', *Dir.glob(File.join(base, 'tasks', 'task_*.yml{,.bak}')).map { |path| path.delete_prefix(base + '/') }]
          when :pins
            Dir.glob(File.join(base, 'pins', '*')).select { |path| File.file?(path) }.map { |path| path.delete_prefix(base + '/') }
          when :pinned_prs then ['pinned_prs.yml']
          else [source]
          end
          names.flat_map { |name| [name, name.end_with?('.bak') ? name : name + '.bak'] }.uniq.filter_map do |name|
            path = File.expand_path(name, base)
            next unless File.file?(path)
            logical = name.delete_suffix('.bak')
            logical = logical.delete_suffix('.yml') if store == :pins
            {store: store, path: path, logical: logical, variant: name.end_with?('.bak') ? 'bak' : 'original'}
          end
        end
        if connection.table_exists?(:pinned_prs) && connection[:pinned_prs].count.positive?
          paths << {store: :pinned_prs, path: 'sqlite:pinned_prs', logical: 'sqlite:pinned_prs', variant: 'legacy-sql'}
        end
        paths.uniq { |entry| entry[:path] }.sort_by { |entry| [OWNED_STORES.keys.index(entry[:store]), entry[:path]] }
      end

      def require_hash(value, location)
        raise ImportError, "#{location}: expected mapping" unless value.is_a?(Hash)
        normalized = value.transform_keys(&:to_s)
        raise ImportError, "#{location}: colliding typed mapping keys" unless normalized.length == value.length
        normalized
      end

      def require_array(value, location)
        raise ImportError, "#{location}: expected array" unless value.is_a?(Array)
        value
      end

      def semantic_digest(value)
        Digest::SHA256.hexdigest(::JSON.generate(canonical_value(value)))
      end

      def canonical_value(value)
        case value
        when Hash then value.transform_keys(&:to_s).sort.to_h.transform_values { |item| canonical_value(item) }
        when Array then value.map { |item| canonical_value(item) }
        when Time, Date then value.iso8601
        else value
        end
      end

      def row_digest(table, row)
        typed = row.to_h do |key, value|
          if key.to_s.end_with?('_json') && value
            [key, ::JSON.parse(value)]
          else
            [key, value]
          end
        end
        semantic_digest(typed)
      end

      def field_equal?(key, left, right)
        return true if left == right
        if key == :repo && left.is_a?(String) && right.is_a?(String)
          identity = Hiiro::RepositoryIdentity.parse(left)
          return true if identity && identity == Hiiro::RepositoryIdentity.parse(right)
        end
        key.to_s.end_with?('_json') && left.is_a?(String) && right.is_a?(String) && ::JSON.parse(left) == ::JSON.parse(right)
      end

      def valid_pin_value!(value, depth = 0)
        raise ImportError, 'Typed JSON exceeds nesting limit or contains cyclic aliases' if depth > 100
        case value
        when Hash
          raise ImportError, 'JSON collections require string keys' unless value.keys.all? { |key| key.is_a?(String) }
          value.each_value { |child| valid_pin_value!(child, depth + 1) }
        when Array then value.each { |child| valid_pin_value!(child, depth + 1) }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          raise ImportError, 'JSON number must be finite' if value.is_a?(Float) && !value.finite?
        else raise ImportError, "Unsupported typed JSON value: #{value.class}"
        end
        value
      end
      def load_yaml_source(entry)
        stream = YAML.parse_stream(entry[:bytes])
        raise ImportError, "#{entry[:path]}: multiple YAML documents are not one owned source" if stream.children.length > 1
        pending = [stream]
        until pending.empty?
          node = pending.pop
          if node.is_a?(Psych::Nodes::Mapping)
            keys = {}
            node.children.each_slice(2) do |key, _value|
              raise ImportError, "#{entry[:path]}: complex YAML mapping keys are unsupported" unless key.is_a?(Psych::Nodes::Scalar)
              raise ImportError, "#{entry[:path]}: Duplicate YAML mapping key: #{key.value}" if keys.key?(key.value)
              keys[key.value] = true
            end
          end
          pending.concat(node.children || [])
        end
        YAML.safe_load(entry[:bytes], permitted_classes: [Symbol, Time, Date], aliases: true)
      end

      def prepare_rows!(entries)
        list = entries.find { |entry| entry[:logical] == 'tasks/tasks.yml' }
        list_data = list && load_yaml_source(list)
        task_names = connection[:tasks].select_map(:name)
        if list
          task_names |= require_array(require_hash(list_data, list[:path]).fetch('tasks'), list[:path]).map do |row|
            name = require_hash(row, list[:path]).fetch('name')
            raise ImportError, "#{list[:path]}: task name must be a string" unless name.is_a?(String)
            name
          end
        end
        entries.each do |entry|
          data = load_yaml_source(entry)
          entry[:rows] = parse_source(entry, data, task_names)
        end
        task_rows = entries.select { |entry| entry[:store] == :tasks }.flat_map { |entry| entry[:rows] }.select { |row| row[:table] == :tasks }
        task_rows.group_by { |row| row[:attributes][:name] }.each_value do |rows|
          merged = {}
          rows.each do |row|
            row[:attributes].each do |key, value|
              raise ImportError, "Conflicting task details: #{merged[:name]}/#{key}" if merged.key?(key) && merged[key] != value
              merged[key] = value
            end
          end
          rows.each { |row| row[:attributes] = merged.dup }
        end
      end

      def parse_source(entry, data, task_names)
        store = entry[:store]
        table = OWNED_STORES.fetch(store)[1]
        location = entry[:path]
        rows = case store
        when :pins
          # pins/h-sha becomes table `sha`; scalars are stored as text, collections as JSON.
          type = File.basename(entry[:logical]).delete_prefix('h-')
          require_hash(data, location).map do |key, value|
            valid_pin_value!(value)
            {resource_type: type, name: key, value: value.is_a?(Hash) || value.is_a?(Array) ? ::JSON.generate(value) : value.to_s}
          end
        when :links
          return parse_links(data, location)
        when :pane_homes
          require_hash(data, location).map { |name, info| {name: name, data_json: ::JSON.generate(require_hash(info, location))} }
        when :apps, :projects, :sounds, :assignments
          mapping = require_hash(data, location)
          mapping = require_hash(mapping['apps'], location) if store == :apps && mapping.keys == ['apps']
          mapping.map do |key, value|
            raise ImportError, "#{location}: #{key} must be a string" unless value.is_a?(String)
            case store
            when :assignments then {worktree: key, branch: value}
            when :projects then {resource_type: 'project', name: key, value: value}
            when :sounds then {resource_type: 'sound', name: key, value: value}
            else {name: key, path: value}
            end
          end
        when :tags
          return require_hash(data, location).flat_map do |namespace, mapping|
            owner = TAG_OWNERS[namespace] || raise(ImportError, "Unknown tag namespace: #{namespace}")
            require_hash(mapping, location).flat_map do |identity, tags|
              require_array(tags, location).map do |tag|
                {table: :tags, attributes: {name: tag, taggable_type: owner[1]}, tag_identity: identity,
                 tag_owner: owner, locator: "#{namespace}/#{identity}/#{tag}"}
              end
            end
          end
        when :todos, :branches, :prs
          wrapper = require_hash(data, location)
          list_key = store == :todos ? 'todos' : store.to_s
          allowed = store == :todos ? [list_key, 'next_id'] : [list_key]
          raise ImportError, "#{location}: unsupported fields #{(wrapper.keys - allowed).join(', ')}" unless (wrapper.keys - allowed).empty?
          if wrapper.key?('next_id')
            raise ImportError, "#{location}: invalid next_id" unless wrapper['next_id'].is_a?(Integer) && wrapper['next_id'].positive?
            entry[:next_id] = wrapper['next_id']
          end
          require_array(wrapper.fetch(list_key), location)
        when :tasks
          mapping = require_hash(data, location)
          if entry[:logical] == 'tasks/tasks.yml'
            raise ImportError, "#{location}: unsupported task list fields" unless (mapping.keys - ['tasks']).empty?
            require_array(mapping.fetch('tasks'), location)
          else
            stem = File.basename(entry[:logical], '.yml').delete_prefix('task_')
            reliable = [mapping['name'], mapping['session']].compact.uniq
            known_names = task_names.select { |name| name.gsub(/[^a-zA-Z0-9_-]/, '_') == stem }
            candidates = reliable.empty? ? known_names : reliable
            candidates = [stem] if candidates.empty? && !stem.include?('_')
            raise ImportError, "#{location}: ambiguous sanitized task name; provide name" unless candidates.length == 1
            name = candidates.first
            known = connection.schema(:tasks).map { |key, _| key.to_s }
            metadata = mapping.reject { |key, _| known.include?(key) || key == 'resources' }
            attributes = mapping.select { |key, _| known.include?(key) || key == 'resources' }.merge('name' => name)
            valid_pin_value!(metadata)
            attributes['metadata_json'] = ::JSON.generate(metadata) unless metadata.empty?
            [attributes]
          end
        else require_array(data, location)
        end
        rows.each_with_index.flat_map do |raw, index|
          row = require_hash(raw, "#{location}/#{index}").transform_keys(&:to_sym)
          resources = store == :tasks ? row.delete(:resources) : nil
          if store == :todos
            flags = %i[done started skip]
            flags.each { |flag| raise ImportError, "#{location}: invalid #{flag}" if row.key?(flag) && ![true, false, nil].include?(row[flag]) }
            row[:status] ||= flags.find { |flag| row[flag] == true }&.to_s || 'not_started'
            flags.each { |flag| row.delete(flag) }
            row[:tags] = row[:tags].join(', ') if row[:tags].is_a?(Array) && row[:tags].all? { |tag| tag.is_a?(String) }
          end
          aliases = {herdr: :herdr_json, tmux: :tmux_json, tags: :tags_json, checks: :checks_json,
                     statusCheckRollup: :check_runs_json, reviews: :reviews_json, depends_on: :depends_on_json,
                     headRefName: :head_ref_name, head_branch: :head_ref_name, isDraft: :is_draft, reviewDecision: :review_decision}
          aliases.each do |from, to|
            next unless row.key?(from)
            value = row.delete(from)
            value = ::JSON.generate(canonical_value(value)) if to.to_s.end_with?('_json')
            raise ImportError, "#{location}: conflicting #{from}/#{to}" if row.key?(to) && row[to] != value
            row[to] = value
          end unless store == :todos
          row[:pinned] = store == :pinned_prs if %i[prs pinned_prs].include?(store) && !row.key?(:pinned)
          row[:worktree] ||= nil if table == :branches
          if table == :prs
            row[:repo] ||= Hiiro::RepositoryIdentity.parse(row[:url])&.path
            row[:herdr_workspace] = row[:tmux_session] if row.key?(:tmux_session) && !row.key?(:herdr_workspace)
          end
          row.transform_values! { |value| value.is_a?(Time) || value.is_a?(Date) ? value.iso8601 : value }
          result = [{table: table, attributes: row, locator: row.key?(:id) ? "id:#{row[:id]}" : "row:#{index}"}]
          if resources
            require_array(resources, location).each_with_index do |resource, ordinal|
              result << {table: :task_resources, attributes: require_hash(resource, location).transform_keys(&:to_sym),
                         task_name: row[:name], locator: "row:#{index}/resource:#{ordinal}"}
            end
          end
          result
        end
      rescue KeyError => error
        raise ImportError, "#{location}: missing #{error.key}"
      end

      # links.yml rows become `link` registry entries: url → value, shorthand →
      # short_name, description, created_at. Names follow link_name; a name
      # taken earlier in the same file falls back to the url. Inline tags
      # attach to the entry by its url.
      def parse_links(data, location)
        taken = []
        require_array(data, location).each_with_index.flat_map do |raw, index|
          row = require_hash(raw, "#{location}/#{index}")
          url = row['url']
          raise ImportError, "#{location}/#{index}: a link needs a url" unless url.is_a?(String) && !url.strip.empty?
          unknown = row.keys - %w[id url description shorthand created_at tags]
          raise ImportError, "#{location}/#{index}: unsupported fields #{unknown.join(', ')}" unless unknown.empty?
          shorthand = row['shorthand'].to_s.empty? ? nil : row['shorthand'].to_s
          description = row['description'].to_s
          name = link_name(url, shorthand, description)
          name = url if taken.include?(name)
          taken << name
          created = row['created_at']
          created = created.iso8601 if created.is_a?(Time) || created.is_a?(Date)
          attributes = {resource_type: 'link', name: name, value: url, short_name: shorthand, description: description,
                        created_at: created&.to_s || Time.now.iso8601}
          attributes[:id] = row['id'] if row.key?('id')
          result = [{table: :registry, attributes: attributes, natural_by: :value, locator: row.key?('id') ? "id:#{row['id']}" : "row:#{index}"}]
          if row['tags']
            require_array(row['tags'], location).each_with_index do |tag, ordinal|
              raise ImportError, "#{location}/#{index}: tags must be strings" unless tag.is_a?(String)
              result << {table: :tags, attributes: {name: tag, taggable_type: 'RegistryEntry'},
                         tag_owner: [:registry, 'RegistryEntry', :value, {resource_type: 'link'}], tag_identity: url, tag_by_natural: true,
                         locator: "row:#{index}/tag:#{ordinal}"}
            end
          end
          result
        end
      end

      def apply_entries!(plan)
        entries = plan[:entries]
        entries.group_by { |entry| entry[:logical] }.each do |logical, variants|
          raise ImportError, "Conflicting source variants: #{logical}" if variants.map { |entry| entry[:checksum] }.uniq.length > 1
        end
        entries.each do |entry|
          known = connection[:migration_sources].where(logical_source_key: entry[:logical]).first
          if known
            unless known[:source_sha256] == entry[:checksum] && known[:parser_version] == PARSER_VERSION
              raise ImportError, "Changed previously imported source: #{entry[:path]}; canonical later writes retained"
            end
            mappings = connection[:migration_rows].where(source_id: known[:id]).all
            changes = mappings.count do |mapping|
              actual = connection[mapping[:target_table].to_sym].where(id: mapping[:target_id]).first
              !actual || row_digest(mapping[:target_table].to_sym, actual) != mapping[:imported_semantic_sha256]
            end
            plan[:report] << {source: entry[:path], status: 'previously-applied', canonical_changes_or_deletions: changes}
            next
          end
          mappings = entry[:rows].flat_map do |item|
            row = item[:attributes].dup
            table = item[:table]
            if item[:task_name]
              task = connection[:tasks].where(name: item[:task_name]).first
              raise ImportError, "Unresolved task: #{item[:task_name]}" unless task
              raise ImportError, 'Task resource identity collision' if row[:task_id] && row[:task_id] != task[:id]
              row[:task_id] = task[:id]
            end
            if item[:tag_owner]
              owner_table, _, name_key, scope = item[:tag_owner]
              candidates = connection[owner_table].where((scope || {}).merge(name_key => item[:tag_identity])).all
              raise ImportError, "Unresolved or ambiguous tag identity: #{item[:tag_identity]}" unless candidates.length == 1
              row[:taggable_id] = item[:tag_by_natural] ? candidates.first[:id].to_s : item[:tag_identity]
            end
            validate_row!(table, row)
            existing = natural_match(table, row, natural_by: item[:natural_by])
            by_id = row[:id] && connection[table].where(id: row[:id]).first
            raise ImportError, "ID/natural identity collision: #{table}/#{row[:id]}" if by_id && existing && by_id[:id] != existing[:id]
            existing ||= by_id
            if existing
              mismatch = row.keys.reject { |key| field_equal?(key, existing[key], row[key]) }
              raise ImportError, "Canonical conflict: #{table}/#{existing[:id]} fields #{mismatch.join(', ')}" unless mismatch.empty?
              id = existing[:id]
            else
              id = connection[table].insert(row)
            end
            actual = verify_row!(table, row, id: id)
            result = [{row_locator: item[:locator], target_table: table.to_s, target_id: id.to_s,
                       imported_semantic_sha256: row_digest(table, actual)}]
            if table == :prs && row[:check_runs_json] && !existing
              Hiiro::PinnedPr[id].sync_check_runs
              Hiiro::CheckRun.where(pr_id: id).order(:id).each_with_index do |run, ordinal|
                validate_row!(:check_runs, run.values)
                verify_row!(:check_runs, run.values, id: run.id)
                result << {row_locator: "#{item[:locator]}/check:#{ordinal}", target_table: 'check_runs', target_id: run.id.to_s,
                           imported_semantic_sha256: row_digest(:check_runs, run.values)}
              end
            end
            result
          end
          raise_sequence!(:todos, entry[:next_id] - 1) if entry[:next_id]
          source_id = connection[:migration_sources].insert(store: entry[:store].to_s, logical_source_key: entry[:logical],
            source_path: entry[:path], variant: entry[:variant], source_sha256: entry[:checksum], parser_version: PARSER_VERSION,
            semantic_sha256: semantic_digest(entry[:rows]), verified_at: Time.now.iso8601)
          mappings.each { |mapping| connection[:migration_rows].insert(mapping.merge(source_id: source_id)) }
          plan[:report] << {source: entry[:path], status: 'verified', rows: mappings.length}
        end
      rescue Sequel::Error => error
        raise ImportError, "Import rejected: #{error.message}"
      end

      def natural_match(table, row, natural_by: nil)
        keys = NATURAL_KEYS[table]
        return nil unless keys && keys.all? { |key| row.key?(key) }
        candidates = if table == :prs
          identity = Hiiro::RepositoryIdentity.parse(row[:repo] || row[:url])
          connection[:prs].where(number: row[:number]).all.select { |candidate| Hiiro::RepositoryIdentity.parse(candidate[:repo] || candidate[:url]) == identity }
        elsif table == :registry && row[:resource_type] == 'link' && natural_by == :value
          by_url = connection[:registry].where(resource_type: 'link', value: row[:value]).all
          by_url.empty? ? connection[:registry].where(row.slice(*keys)).all : by_url
        else
          connection[table].where(row.slice(*keys)).all
        end
        raise ImportError, "Ambiguous canonical identity: #{table}/#{row.slice(*keys)}" if candidates.length > 1
        candidates.first
      end

      def validate_row!(table, row)
        schema = connection.schema(table).to_h
        unknown = row.keys - schema.keys
        raise ImportError, "#{table}: unsupported fields #{unknown.join(', ')}" unless unknown.empty?
        row.each do |key, value|
          info = schema.fetch(key)
          if value.nil?
            raise ImportError, "#{table}/#{key}: null not allowed" if info[:allow_null] == false
            next
          end
          valid = case info[:type]
          when :integer then value.is_a?(Integer)
          when :boolean then value == true || value == false
          when :string then value.is_a?(String)
          when :float then value.is_a?(Numeric) && value.finite?
          else false
          end
          raise ImportError, "#{table}/#{key}: invalid #{info[:type]} value" unless valid
          if key.to_s.end_with?('_json')
            decoded = ::JSON.parse(value)
            shape = case key
            when :tags_json, :depends_on_json, :check_runs_json, :review_nodes_json then Array
            when :herdr_json, :tmux_json, :checks_json, :reviews_json, :metadata_json, :meta_json, :data_json, :record_json then Hash
            end
            raise ImportError, "#{table}/#{key}: invalid JSON shape" if shape && !decoded.nil? && !decoded.is_a?(shape)
            if key == :tags_json && decoded && !decoded.all? { |tag| tag.is_a?(String) }
              raise ImportError, "#{table}/#{key}: tags must be strings"
            end
            if key == :check_runs_json && decoded && !decoded.all? { |run| run.is_a?(Hash) }
              raise ImportError, 'prs/check_runs_json: check runs must be mappings'
            end
            # Legacy positive integers are retained until qualified; new entries are owner/name#N.
            if key == :depends_on_json && decoded && !decoded.all? { |dep| (dep.is_a?(Integer) && dep.positive?) || (dep.is_a?(String) && Hiiro::PullRequestReference.qualified(dep)&.to_s == dep) }
              raise ImportError, 'prs/depends_on_json: dependencies must be owner/name#N or legacy PR numbers'
            end
          end
        end
        schema.each do |key, info|
          if !row.key?(key) && info[:allow_null] == false && !info[:primary_key] && info[:default].nil?
            raise ImportError, "#{table}: missing required #{key}"
          end
        end
        raise ImportError, "#{table}: invalid id" if row[:id].is_a?(Integer) && !row[:id].positive?
        raise ImportError, 'todos: invalid status' if table == :todos && !Hiiro::TodoItem::STATUSES.include?(row[:status])
        raise ImportError, 'prs: number must be a positive integer' if table == :prs && (!row[:number].is_a?(Integer) || !row[:number].positive?)
        raise ImportError, 'prs: invalid qualified repository identity' if table == :prs && row[:repo] && !Hiiro::RepositoryIdentity.parse(row[:repo])
        if table == :reminders
          Hiiro::Reminder.validate_fields!(row.reject { |key, _| key == :id })
          raise ImportError, 'reminders: invalid interval' if row[:interval] && !Hiiro::Duration.parse(row[:interval])
        end
      end

      def verify_row!(table, row, identity)
        actual = connection[table].where(identity).first
        raise ImportError, "Reload mismatch: #{table}/#{identity}" unless actual && row.all? { |key, value| field_equal?(key, actual[key], value) }
        model = MODELS.find { |owner| owner.table_name == table }
        if model && identity.key?(:id)
          loaded = model[identity[:id]]
          raise ImportError, "Owner reload mismatch: #{table}/#{identity}" unless loaded && loaded.values == actual
        end
        actual
      end

      def insert_registry_row(resource_type, name, value)
        rows = connection[:registry]
        return if rows.where(resource_type: resource_type, name: name).count > 0

        rows.insert(resource_type: resource_type, name: name, value: value, created_at: Time.now.iso8601)
      end

      def import_legacy_pins_table
        return unless connection.table_exists?(:pins)

        connection[:pins].each do |row|
          insert_registry_row(row[:command].to_s.delete_prefix('h-'), row[:key], row[:value_json])
        end
      rescue Sequel::Error => e
        warn "Hiiro::DB: failed to import pins table: #{e}"
      end

      def import_legacy_links_table
        return unless connection.table_exists?(:links)

        new_ids = connection[:links].order(:id).each_with_object({}) do |row, ids|
          id = insert_link_row(row[:url], row[:shorthand], row[:description], row[:created_at])
          ids[row[:id].to_s] = id if id
        end
        copy_link_tags(new_ids)
      rescue Sequel::Error => e
        warn "Hiiro::DB: failed to import links table: #{e}"
      end

      def import_legacy_projects_table
        return unless connection.table_exists?(:projects)

        connection[:projects].order(:name).each do |row|
          insert_registry_row('project', row[:name].to_s, row[:path].to_s)
        end
      rescue Sequel::Error => e
        warn "Hiiro::DB: failed to import projects table: #{e}"
      end

      # Returns the id of the row holding url (new or already present), or nil.
      def insert_link_row(url, shorthand, description, created_at)
        url = url.to_s
        return if url.empty?

        rows = connection[:registry].where(resource_type: 'link')
        existing = rows.where(value: url).get(:id)
        return existing if existing

        name = link_name(url, shorthand, description)
        return if rows.where(name: name).count > 0

        created_at = created_at.iso8601 if created_at.respond_to?(:iso8601)
        connection[:registry].insert(
          resource_type: 'link',
          name:          name,
          value:         url,
          short_name:    shorthand.to_s.empty? ? nil : shorthand.to_s,
          description:   description,
          created_at:    created_at&.to_s || Time.now.iso8601
        )
      end

      # Copies rather than moves the 'Link' tags so the retired table stays intact.
      def copy_link_tags(new_ids)
        return unless connection.table_exists?(:tags)

        tags = connection[:tags]
        tags.where(taggable_type: 'Link').order(:id).all.each do |t|
          new_id = new_ids[t[:taggable_id].to_s] or next
          target = { name: t[:name], taggable_type: 'RegistryEntry', taggable_id: new_id.to_s }
          next if tags.where(target).count > 0

          tags.insert(target.merge(created_at: t[:created_at]))
        end
      end

      def validate_relations!
        %i[task_resources registry].each do |table|
          connection[table].exclude(task_id: nil).each do |row|
            raise ImportError, "Unresolved #{table} task_id #{row[:task_id]}" unless connection[:tasks].where(id: row[:task_id]).count == 1
          end
        end
        connection[:tags].each do |row|
          tag = Hiiro::Tag[row[:id]]
          raise ImportError, "Unresolved tag owner #{row[:taggable_type]}/#{row[:taggable_id]}" unless tag.taggable
        end
        if connection.schema(:check_runs).any? { |key, _| key == :pr_id }
          connection[:check_runs].exclude(pr_id: nil).each do |row|
            raise ImportError, "Unresolved check run pr_id #{row[:pr_id]}" unless connection[:prs].where(id: row[:pr_id]).count == 1
          end
        end
      end
    end

    module JSON
      def self.dump(val) = val.nil? ? nil : ::JSON.generate(val)
      def self.load(str) = str.nil? ? nil : ::JSON.parse(str)
    end
  end
end

