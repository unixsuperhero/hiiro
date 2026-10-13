# frozen_string_literal: true

require 'json'
require 'time'

class MCPRegistry
  MIGRATION = 'mcp_json_catalogs_to_sqlite'
  SYNC_TYPE = 'mcp-sync'
  IDENTITY_FIELDS = %w[source transport url command].freeze
  CATALOG_FIELDS = %w[discovered_at initialize tools].freeze
  PRIVATE_FIELDS = %w[
    connection args env environment headers http_headers env_http_headers
    bearer_token_env_var env_vars created_at updated_at
  ].freeze

  def initialize(legacy_dir: nil)
    # Hiiro::DB.setup! owns the mcps schema, beside the canonical tables it exports.
    Hiiro::DB.setup!
    @db = Hiiro::DB.connection
    @records = @db[:mcps]
    legacy_dir ||= File.join(Hiiro::Config::DATA_DIR, 'mcp') unless ENV.key?('HIIRO_TEST_DB')
    migrate_legacy!(File.expand_path(legacy_dir)) if legacy_dir
  end

  def all
    @records.order(:name).all.map { |row| decode(row) }
  end

  def find(name)
    row = @records.where(name: name).first
    decode(row) if row
  end

  def register(record)
    metadata = record.reject { |key, _| CATALOG_FIELDS.include?(key) }
    @db.transaction(mode: :immediate) do
      previous = find(metadata.fetch('name'))
      if previous && IDENTITY_FIELDS.all? { |field| previous[field] == metadata[field] }
        metadata = previous.merge(metadata)
      end
      persist(metadata)
    end
  end

  def save(snapshot)
    @db.transaction(mode: :immediate) { persist(snapshot) }
  end

  def remove(name)
    @records.where(name: name).delete.positive?
  end

  def sync_state(path)
    row = @db[:registry].where(resource_type: SYNC_TYPE, name: File.expand_path(path)).first
    row ? JSON.parse(row.fetch(:meta_json)) : {}
  end

  def save_sync_state(path, state)
    json = JSON.generate(state)
    @db[:registry].insert_conflict(
      target: %i[resource_type name], update: { meta_json: json }
    ).insert(resource_type: SYNC_TYPE, name: File.expand_path(path), meta_json: json,
             created_at: Time.now.utc.iso8601(6))
    state
  end

  private

  def decode(row)
    JSON.parse(row.fetch(:record_json)).merge(
      'created_at' => row.fetch(:created_at), 'updated_at' => row.fetch(:updated_at)
    )
  end

  def persist(record)
    public = record.reject { |key, _| PRIVATE_FIELDS.include?(key) }
    name = public.fetch('name')
    now = Time.now.utc.iso8601(6)
    json = JSON.generate(public)
    @records.insert_conflict(
      target: :name, update: { record_json: json, updated_at: now }
    ).insert(name: name, record_json: json, created_at: now, updated_at: now)
    find(name)
  end

  def migrate_legacy!(directory)
    migration = @db[:schema_migrations].where(name: MIGRATION)
    return unless migration.empty?
    if File.exist?(directory) && !File.directory?(directory)
      raise ArgumentError, "legacy MCP catalog path is not a directory: #{directory}"
    end

    records = {}
    Dir.glob(File.join(directory, '*.json')).sort.each do |path|
      record = read_legacy(path)
      name = record.fetch('name')
      raise ArgumentError, "duplicate legacy MCP name #{name}: #{path}" if records.key?(name)
      records[name] = record
    end

    # Validate every backup first; keep existing SQLite rows and all backups.
    @db.transaction(mode: :immediate) do
      if migration.empty?
        records.each do |name, record|
          persist(record) unless @records.where(name: name).first
        end
        @db[:schema_migrations].insert(name: MIGRATION, ran_at: Time.now.utc.iso8601(6))
      end
    end
  end

  def read_legacy(path)
    record = JSON.parse(File.read(path))
    raise ArgumentError, 'catalog must be an object' unless record.is_a?(Hash)
    require_string!(record['name'], 'catalog name')
    source = record['source']
    raise ArgumentError, 'source must be an object' unless source.is_a?(Hash)
    fields = case source['kind']
             when 'config' then %w[path name]
             when 'codex' then %w[name cwd]
             when 'url', 'registry' then %w[url]
             else raise ArgumentError, 'unknown source kind'
             end
    fields.each { |field| require_string!(source[field], "source #{field}") }
    if source.key?('name') && source['name'] != record['name']
      raise ArgumentError, 'source name must equal catalog name'
    end
    if source['kind'] == 'config'
      keys = source['keys']
      unless keys.is_a?(Array) && keys.all? { |key| key.is_a?(String) && !key.empty? }
        raise ArgumentError, 'source keys must be an array of configuration keys'
      end
    end
    %w[cwd cwd_base].each do |field|
      require_string!(source[field], "source #{field}") if source.key?(field)
    end
    tools = record['tools']
    raise ArgumentError, 'tools must be an array' unless tools.is_a?(Array)
    tools.each do |tool|
      raise ArgumentError, 'each tool must be an object' unless tool.is_a?(Hash)
      require_string!(tool['name'], 'tool name')
    end
    record
  rescue JSON::ParserError
    raise ArgumentError, "invalid JSON in legacy MCP catalog #{path}"
  rescue ArgumentError => error
    raise ArgumentError, "invalid legacy MCP catalog #{path}: #{error.message}"
  rescue SystemCallError => error
    raise ArgumentError, "cannot read legacy MCP catalog #{path}: #{error.class}"
  end

  def require_string!(value, label)
    unless value.is_a?(String) && !value.strip.empty?
      raise ArgumentError, "#{label} must be a nonempty string"
    end
  end
end
