require 'json'
require 'sequel'
require 'time'

class Hiiro
  module DB
    MODELS = []

    DB_FILE = Hiiro::Config.path('hiiro.db')

    class << self
      def register(cls)
        MODELS << cls
      end

      def connection
        @connection ||= begin
          url = ENV.fetch('HIIRO_TEST_DB', "sqlite://#{DB_FILE}")
          db = Sequel.connect(url, logger: nil)
          db.run('PRAGMA journal_mode=WAL')
          Sequel::Model.db = db
          db
        end
      end
      alias db connection

      def setup!
        return if @setup_done
        @setup_done = true

        conn = connection

        conn.create_table?(:schema_migrations) do
          String :name, primary_key: true
          String :ran_at
        end

        MODELS.each do |cls|
          cls.create_table!(conn)
          # Clear all schema-related caches on the model and its anonymous Sequel
          # parent class. When require_valid_table=false and the table didn't exist
          # at class-definition time, Sequel caches empty results for @db_schema,
          # @columns, and @setter_methods. Re-invoking get_db_schema after tables
          # are created re-introspects and re-defines column getter/setter methods.
          [cls, cls.superclass].each do |klass|
            klass.instance_variable_set(:@db_schema, nil)
            klass.instance_variable_set(:@columns, nil)
            klass.instance_variable_set(:@setter_methods, nil)
          end
          cls.send(:get_db_schema)
        end

        migrate_yaml! unless migrated? || ENV['HIIRO_TEST_DB']
      end

      def migrated?
        connection[:schema_migrations].count > 0
      rescue Sequel::DatabaseError
        false
      end

      def dual_write?
        !connection[:schema_migrations].where(name: 'full_migration').count.positive?
      rescue
        true  # safe default: keep writing YAML if DB is unavailable
      end

      def disable_dual_write!
        connection[:schema_migrations].insert_conflict.insert(name: 'full_migration', ran_at: Time.now.iso8601)
      end

      private

      def migrate_yaml!
        base = Hiiro::Config::BASE_DIR

        import_todos(base)
        import_links(base)
        import_branches(base)
        import_prs(base)
        import_pinned_prs(base)
        import_tasks(base)
        import_assignments(base)
        import_apps(base)
        import_projects(base)
        import_pane_homes(base)
        import_pins(base)
        import_reminders(base)
        import_tags(base)

        connection[:schema_migrations].insert(name: 'yaml_import', ran_at: Time.now.iso8601)
      rescue => e
        warn "Hiiro::DB migration error: #{e}"
      end

      def load_yaml(path)
        return nil unless File.exist?(path)
        YAML.load(File.read(path))
      rescue => e
        warn "Hiiro::DB: failed to load YAML #{path}: #{e}"
        nil
      end

      def bak(path)
        File.rename(path, path + '.bak') if File.exist?(path)
      end

      def import_todos(base)
        path = File.join(base, 'todo.yml')
        data = load_yaml(path)
        return unless data

        todos = data.is_a?(Hash) ? (data['todos'] || []) : []
        todos.each do |row|
          next unless row.is_a?(Hash)
          connection[:todos].insert(row.transform_keys(&:to_s))
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import todos: #{e}"
      end

      def import_links(base)
        path = File.join(base, 'links.yml')
        data = load_yaml(path)
        return unless data

        links = data.is_a?(Array) ? data : []
        links.each do |row|
          next unless row.is_a?(Hash)
          connection[:links].insert(row.transform_keys(&:to_s))
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import links: #{e}"
      end

      def import_branches(base)
        path = File.join(base, 'branches.yml')
        data = load_yaml(path)
        return unless data

        branches = data.is_a?(Hash) ? (data['branches'] || []) : []
        branches.each do |row|
          next unless row.is_a?(Hash)
          normalized = row.transform_keys(&:to_s)
          tmux = normalized.delete('tmux')
          normalized['tmux_json'] = ::JSON.generate(tmux) if tmux
          connection[:branches].insert(normalized)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import branches: #{e}"
      end

      def import_prs(base)
        path = File.join(base, 'prs.yml')
        data = load_yaml(path)
        return unless data

        prs = data.is_a?(Hash) ? (data['prs'] || []) : []
        prs.each do |row|
          next unless row.is_a?(Hash)
          normalized = row.transform_keys(&:to_s)
          tmux = normalized.delete('tmux')
          normalized['tmux_json'] = ::JSON.generate(tmux) if tmux
          connection[:prs].insert(normalized)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import prs: #{e}"
      end

      def import_pinned_prs(base)
        path = File.join(base, 'pinned_prs.yml')
        data = load_yaml(path)
        return unless data

        prs = data.is_a?(Array) ? data : []
        json_fields = %w[checks statusCheckRollup reviews tags depends_on]
        prs.each do |row|
          next unless row.is_a?(Hash)
          normalized = row.transform_keys(&:to_s)
          json_fields.each do |field|
            normalized[field] = ::JSON.generate(normalized[field]) if normalized.key?(field)
          end
          connection[:pinned_prs].insert(normalized)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import pinned_prs: #{e}"
      end

      def import_tasks(base)
        tasks_file = File.join(base, 'tasks', 'tasks.yml')
        data = load_yaml(tasks_file)
        return unless data

        tasks = data.is_a?(Hash) ? (data['tasks'] || []) : []

        details_map = {}
        Dir.glob(File.join(base, 'tasks', 'task_*.yml')).each do |detail_file|
          detail_data = load_yaml(detail_file)
          next unless detail_data.is_a?(Hash)
          stem = File.basename(detail_file, '.yml').sub(/^task_/, '')
          details_map[stem] = detail_data
        end

        tasks.each do |row|
          next unless row.is_a?(Hash)
          normalized = row.transform_keys(&:to_s)
          name = normalized['name']

          if name && (details = details_map[name])
            normalized['tree']    ||= details['tree']
            normalized['session'] ||= details['session']
            normalized['app']     ||= details['app']
          end

          connection[:tasks].insert(normalized)
        end
        bak(tasks_file)
      rescue => e
        warn "Hiiro::DB: failed to import tasks: #{e}"
      end

      def import_assignments(base)
        path = File.join(base, 'tasks', 'assignments.yml')
        data = load_yaml(path)
        return unless data

        assignments = data.is_a?(Hash) ? data : {}
        assignments.each do |worktree, branch|
          connection[:assignments].insert('worktree' => worktree.to_s, 'branch' => branch.to_s)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import assignments: #{e}"
      end

      def import_apps(base)
        path = File.join(base, 'apps.yml')
        data = load_yaml(path)
        return unless data

        apps = data.is_a?(Hash) ? data : {}
        apps.each do |name, app_path|
          connection[:apps].insert('name' => name.to_s, 'path' => app_path.to_s)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import apps: #{e}"
      end

      def import_projects(base)
        path = File.join(base, 'projects.yml')
        data = load_yaml(path)
        return unless data

        projects = data.is_a?(Hash) ? data : {}
        projects.each do |name, proj_path|
          connection[:projects].insert('name' => name.to_s, 'path' => proj_path.to_s)
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import projects: #{e}"
      end

      def import_pane_homes(base)
        path = File.join(base, 'pane_homes.yml')
        data = load_yaml(path)
        return unless data

        pane_homes = data.is_a?(Hash) ? data : {}
        pane_homes.each do |name, info|
          next unless info.is_a?(Hash)
          connection[:pane_homes].insert(
            'name'      => name.to_s,
            'data_json' => ::JSON.generate(info)
          )
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import pane_homes: #{e}"
      end

      def import_pins(base)
        pins_dir = File.join(base, 'pins')
        return unless Dir.exist?(pins_dir)

        Dir.glob(File.join(pins_dir, '*.yml')).each do |pin_file|
          command = File.basename(pin_file, '.yml')
          data = load_yaml(pin_file)
          next unless data.is_a?(Hash)

          data.each do |key, value|
            connection[:pins].insert(
              'command'    => command,
              'key'        => key.to_s,
              'value_json' => value.is_a?(String) ? value : ::JSON.generate(value)
            )
          end
          bak(pin_file)
        end
      rescue => e
        warn "Hiiro::DB: failed to import pins: #{e}"
      end

      def import_reminders(base)
        path = File.join(base, 'reminders.yml')
        data = load_yaml(path)
        return unless data

        reminders = data.is_a?(Array) ? data : []
        reminders.each do |row|
          next unless row.is_a?(Hash)
          connection[:reminders].insert(row.transform_keys(&:to_s))
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import reminders: #{e}"
      end

      def import_tags(base)
        path = File.join(base, 'tags.yml')
        data = load_yaml(path)
        return unless data.is_a?(Hash)

        data.each do |namespace, keys|
          next unless keys.is_a?(Hash)
          keys.each do |key, tags|
            next unless tags.is_a?(Array)
            tags.each do |tag|
              connection[:tags].insert(
                'namespace' => namespace.to_s,
                'key'       => key.to_s,
                'tag'       => tag.to_s
              )
            end
          end
        end
        bak(path)
      rescue => e
        warn "Hiiro::DB: failed to import tags: #{e}"
      end
    end

    module JSON
      def self.dump(val)
        val.nil? ? nil : ::JSON.generate(val)
      end

      def self.load(str)
        str.nil? ? nil : ::JSON.parse(str)
      end
    end
  end
end

# Establish connection eagerly so Sequel::Model subclasses can be defined at
# require time. By default Sequel 5 sets require_valid_table=true which raises
# if the table doesn't exist when the class is defined — we disable that so
# models load cleanly and tables are created later in DB.setup!.
Hiiro::DB.connection
Sequel::Model.require_valid_table = false
