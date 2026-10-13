# frozen_string_literal: true

require 'json'
require 'uri'
require 'digest'
require 'open3'
require 'time'
require 'shellwords'

class MCPCatalog
  def initialize(config: nil, agent: nil)
    @config, @agent = config, agent
  end

  def store
    @store ||= MCPRegistry.new
  end

  def configured
    return json_servers(File.expand_path(@config)) if @config
    raise %(unknown agent #{@agent}; choose #{MCPSync::AGENT_TARGETS.keys.join(', ')}) if @agent && !MCPSync::AGENT_TARGETS.key?(@agent)

    records = []
    MCPSync::AGENT_TARGETS.each do |agent, target|
      next if agent == 'codex' || (@agent && @agent != agent)
      path, keys, = target.call(Dir.home)
      paths = [path]
      paths << File.join(Dir.pwd, MCPSync::PROJECT_PATHS[agent]) if MCPSync::PROJECT_PATHS[agent]
      paths << File.join(Dir.pwd, '.omp/mcp.json') if agent == 'omp'
      paths << File.join(Dir.pwd, '.vscode/mcp.json') if agent == 'vscode'
      paths.compact.uniq.each do |candidate|
        records.concat(json_servers(candidate, keys: keys, agent: agent)) if File.file?(candidate)
      end
    end
    if !@agent || @agent == 'codex'
      begin
        records.concat(codex_servers)
      rescue Errno::ENOENT
        raise 'codex executable not found' if @agent == 'codex'
      end
    end
    records.sort_by { |server| [server['name'], server['source'].to_json] }
  end

  def codex_servers(cwd = Dir.pwd)
    cwd = File.expand_path(cwd)
    stdout, _stderr, status = Open3.capture3('codex', 'mcp', 'list', '--json', chdir: cwd)
    raise %(codex mcp list failed (exit #{status.exitstatus})) unless status.success?
    JSON.parse(stdout).map do |server|
      record(server.fetch('name'), server.fetch('transport'),
             { 'kind' => 'codex', 'name' => server.fetch('name'), 'cwd' => cwd },
             agent: 'codex', enabled: server['enabled'] != false)
    end
  end

  def json_servers(path, keys: nil, agent: nil, workspace: nil)
    path = File.expand_path(path)
    data = JSON.parse(File.read(path))
    raise %(expected configuration object in #{path}) unless data.is_a?(Hash)
    keys ||= [%w[mcpServers servers mcp].find { |key| data[key].is_a?(Hash) } || 'mcpServers']
    servers = keys.inject(data) { |value, key| value.fetch(key, {}) }
    raise %(expected server object in #{path}) unless servers.is_a?(Hash)
    workspace ||= agent ? Dir.pwd : File.dirname(path)
    servers.map do |name, entry|
      raise %(invalid server #{name} in #{path}) unless entry.is_a?(Hash)
      record(name, entry, { 'kind' => 'config', 'path' => path, 'keys' => keys, 'name' => name,
                            'cwd' => workspace, 'cwd_base' => %w[vscode opencode].include?(agent) ? workspace : File.dirname(path) },
             agent: agent, enabled: entry['enabled'] != false && entry['disabled'] != true)
    end
  end

  def record(name, entry, source, agent: nil, enabled: true)
    raise 'server name must be a nonempty string' unless name.is_a?(String) && !name.strip.empty?
    raise %(invalid server definition for #{name}) unless entry.is_a?(Hash)
    if entry['command'].is_a?(Array)
      entry = entry.merge('command' => entry['command'].first, 'args' => entry['command'].drop(1) + Array(entry['args']))
    end
    entry = entry.merge('env' => entry['environment']) if entry['environment'] && !entry['env']
    url = entry['url'] || entry['httpUrl'] || entry['serverUrl']
    executable = entry['command'] && File.basename(entry['command'])
    executable = '(see source configuration)' if executable && !executable.match?(/\A[A-Za-z0-9_.-]+\z/)
    transport = entry['command'] ? 'stdio' : (entry['type'] == 'sse' ? 'sse' : 'http')
    { 'name' => name, 'transport' => transport, 'source' => source,
      'agent' => agent, 'enabled' => enabled, 'url' => url && safe_url(url),
      'command' => executable, 'env_names' => ((entry['env'] || {}).keys + Array(entry['env_vars'])).uniq,
      'header_names' => (entry['headers'] || entry['http_headers'] || {}).keys,
      'auth_env_names' => (Array(entry['bearer_token_env_var']) + (entry['env_http_headers'] || {}).values).uniq,
      'connection' => entry }.compact
  end

  def safe_url(url)
    return '(URL from environment)' if url.match?(/\$\{|\{env:/)
    uri = URI.parse(url)
    uri.userinfo = nil
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  end

  def public_record(server)
    server.reject { |key, _| key == 'connection' }
  end

  def registry
    store.all
  end

  def saved
    registry.select { |server| server['discovered_at'] && server['tools'].is_a?(Array) }
  end

  def cached(name)
    snapshot = store.find(name)
    return snapshot if snapshot && snapshot['discovered_at'] && snapshot['tools'].is_a?(Array)
    raise %(no saved catalog for #{name}; run: h mcp discover #{name.shellescape} [--config FILE | --agent NAME | --url URL])
  end

  def register(server, headers_env: nil)
    registration = public_record(server)
    if headers_env
      raise '--headers-env on add requires an explicit --url' unless server.dig('source', 'kind') == 'url'
      raise '--headers-env must name an environment variable' unless headers_env.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      registration = registration.merge('headers_env' => headers_env, 'credential_scope' => credential_scope(server))
    end
    store.register(registration)
  end

  def resolve(name, url: nil)
    if url
      raise 'URLs with credentials or query parameters must be referenced through --config instead' unless safe_url(url) == url
      raise '--url must be an absolute HTTP or HTTPS URL' unless URI.parse(url).is_a?(URI::HTTP) && URI.parse(url).host
      return record(name, { 'url' => url }, { 'kind' => 'url', 'url' => url })
    end
    if @config || @agent
      candidates = configured.select { |server| server['name'] == name }
      raise %(#{name} exists in multiple configs; select --config explicitly) if candidates.length > 1
      return candidates.first if candidates.first
      raise %(no server #{name} in selected configuration)
    end

    registration = store.find(name)
    raise %(no registered server #{name}; run: h mcp add #{name.shellescape} --url URL, h mcp import --config FILE, or select --config, --agent, or --url explicitly) unless registration
    source = registration.fetch('source')
    case source.fetch('kind')
    when 'config'
      server = json_servers(source.fetch('path'), keys: source.fetch('keys'), agent: registration['agent'], workspace: source['cwd']).find { |candidate| candidate['name'] == name }
      raise %(#{name} was removed from #{source['path']}) unless server
      server.merge('source' => source)
    when 'codex'
      server = codex_servers(source.fetch('cwd')).find { |candidate| candidate['name'] == name }
      raise %(#{name} is no longer configured in its saved Codex directory) unless server
      server.merge('source' => source)
    when 'url', 'registry'
      record(name, { 'url' => source.fetch('url') }, source, agent: registration['agent'], enabled: registration['enabled'])
    else
      raise %(unsupported stored source for #{name}; remove it and add an explicit source)
    end
  end

  def expand_env(value, workspace: Dir.pwd)
    value.gsub(/\$\{([^}]+)\}|\{env:([^}]+)\}/) do
      reference = Regexp.last_match(1) || %(env:#{Regexp.last_match(2)})
      if reference == 'workspaceFolder'
        workspace
      else
        reference = reference.delete_prefix('env:')
        name, default = reference.split(':-', 2)
        raise 'unsupported client-only variable reference; configure a literal value or environment variable' unless name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        ENV.key?(name) ? ENV.fetch(name) : default || ENV.fetch(name)
      end
    end
  end

  def server_url(server)
    raise %(#{server['name']} uses stdio and has no HTTP URL) if server['transport'] == 'stdio'
    entry = server.fetch('connection')
    url = entry['url'] || entry['httpUrl'] || entry.fetch('serverUrl')
    expand_env(url, workspace: server.dig('source', 'cwd') || Dir.pwd)
  end

  def connection_settings(server, headers_env: nil)
    raise %(#{server['name']} is disabled in its source configuration) unless server['enabled']
    entry = server.fetch('connection')
    workspace = server.dig('source', 'cwd') || Dir.pwd
    if server['transport'] == 'stdio'
      command = expand_env(entry.fetch('command'), workspace: workspace)
      args = Array(entry['args']).map { |arg| expand_env(arg, workspace: workspace) }
      env = (entry['env'] || {}).transform_values { |value| value.nil? ? nil : expand_env(value.to_s, workspace: workspace) }
      base = server.dig('source', 'cwd_base') || workspace
      cwd = entry['cwd'] ? File.expand_path(expand_env(entry['cwd'], workspace: workspace), base) : workspace
      { command: '/bin/sh', args: ['-c', 'cd "$1" && shift && exec "$@"', 'h-mcp', cwd, command, *args], env: env }
    else
      raise 'legacy SSE config is not Streamable HTTP; use the server HTTP endpoint via --url or --config' if server['transport'] == 'sse'
      headers = (entry['headers'] || entry['http_headers'] || {}).transform_values { |value| expand_env(value, workspace: workspace) }
      (entry['env_http_headers'] || {}).each { |key, var| headers[key] = ENV.fetch(var) }
      token_env = entry['bearer_token_env_var']
      headers['Authorization'] = %(Bearer #{ENV.fetch(token_env)}) if token_env
      headers_env ||= self.headers_env(server)
      if headers_env
        extra = JSON.parse(ENV.fetch(headers_env))
        raise '--headers-env must contain a JSON object of string headers' unless extra.is_a?(Hash) && extra.values.all? { |value| value.is_a?(String) }
        headers.merge!(extra)
      end
      { url: server_url(server), headers: headers }
    end
  end

  def connect(server, headers_env: nil, timeout: 30)
    settings = connection_settings(server, headers_env: headers_env)
    gem 'mcp', '~> 1.5'
    require 'mcp'
    if server['transport'] == 'stdio'
      transport = MCP::Client::Stdio.new(**settings, read_timeout: timeout)
    else
      require 'faraday'
      transport = MCP::Client::HTTP.new(**settings) do |connection|
        connection.options.timeout = timeout
        connection.options.open_timeout = timeout
      end
    end
    client = MCP::Client.new(transport: transport)
    client.connect
    yield client
  ensure
    begin
      transport&.close
    rescue StandardError => error
      warn %(MCP connection cleanup failed: #{error.class})
    end
  end

  def discover(server, **options)
    options[:headers_env] ||= headers_env(server)
    connect(server, **options) do |client|
      tools, cursors, cursor = [], [], nil
      loop do
        page = client.list_tools(cursor: cursor)
        tools.concat(page.tools.map do |tool|
          { 'name' => tool.name, 'description' => tool.description, 'inputSchema' => tool.input_schema,
            'outputSchema' => tool.output_schema, 'annotations' => tool.annotations }.compact
        end)
        cursor = page.next_cursor
        break if cursor.nil?
        raise 'server repeated a tools/list cursor; catalog was not saved' if cursors.include?(cursor)
        raise 'tools/list exceeded 1000 pages; catalog was not saved' if cursors.length >= 999
        cursors << cursor
      end
      snapshot = public_record(server).merge('discovered_at' => Time.now.utc.iso8601,
                                             'initialize' => client.server_info, 'tools' => tools, 'credential_scope' => credential_scope(server))
      snapshot['headers_env'] = options[:headers_env] if options[:headers_env]
      store.save(snapshot)
    end
  end

  def tool(name, tool_name)
    cached(name).fetch('tools').find { |tool| tool['name'] == tool_name } ||
      raise(%(no saved tool #{tool_name} on #{name}; run: h mcp discover #{name.shellescape}))
  end

  def credential_scope(server)
    address = server.fetch('connection').slice('url', 'httpUrl', 'serverUrl').transform_values do |url|
      expand_env(url, workspace: server.dig('source', 'cwd') || Dir.pwd)
    end
    Digest::SHA256.hexdigest(JSON.generate([server['source'], address]))
  end

  def headers_env(server)
    snapshot = store.find(server.fetch('name'))
    return nil unless snapshot && snapshot['headers_env']
    snapshot['headers_env'] if snapshot['credential_scope'] == credential_scope(server)
  end

  def data(result)
    return result['structuredContent'] if result.key?('structuredContent')
    content = result.fetch('content', [])
    unless content.length == 1 && content.first['type'] == 'text'
      raise 'result has no structuredContent or single JSON text block; omit --data to inspect the full result'
    end
    JSON.parse(content.first.fetch('text'))
  rescue JSON::ParserError
    raise 'tool returned plain text, not JSON; omit --data to inspect the full result'
  end
end

module MCPCommands
  GUIDE = <<~TEXT
    Local, no-AI MCP workflow:
      h mcp list [--json]                    Local registrations, without connecting
      h mcp info SERVER                     Full local registration and saved catalog
      h mcp add SERVER --url URL             Register a Streamable HTTP URL without connecting
      h mcp add SERVER --config FILE         Register the exact name from a JSON config
      h mcp add SERVER --agent NAME          Register the exact name from a client configuration
      h mcp import [--config FILE | --agent NAME]
                                            Register configured inventory without connecting
      h mcp remove SERVER                   Delete the registration and its saved catalog
      h mcp configured [--agent codex]       Current client inventory, without registering it
      h mcp discover SERVER                 Resolve a registered source and save all tool schemas
      h mcp discover SERVER --url URL       Connect directly to an explicit HTTP source
      h mcp discover --all                  Discover enabled local registrations independently
      h mcp discover --all --config FILE    Discover enabled servers from an explicit config
      h mcp saved                           Discovered catalogs, offline, including zero-tool servers
      h mcp tools SERVER                    Saved tool names and descriptions, offline
      h mcp tool SERVER TOOL                Saved input/output schemas and call instructions
      h mcp test SERVER                     SDK initialize handshake only; no tool calls
      h mcp url SERVER                      Current HTTP URL; stdio servers have no URL
      h mcp call SERVER TOOL --args '{}'    Direct call; print the full MCP result as JSON
      h mcp call SERVER TOOL --args-file - --data
                                            Read JSON arguments from stdin and extract JSON data
      h mcp sync AGENT [--dry-run]          Explicitly export registered connections to a client
      h mcp status [AGENT] [--json]         Compare exported definitions without connecting
    Storage is the existing Hiiro main database, ~/.config/hiiro/hiiro.db, in mcps.
    Old ~/.local/share/hiiro/mcp JSON catalogs migrate once and remain as backups.
    Registration and discovery are separate. Successful discovery also registers the source.
    Import without source flags reads all supported current client configurations. Duplicate
    names are rejected before registration; select a single config to disambiguate them.
    Unregistered names require add/import or an explicit --url, --config, or --agent.
    Registered sources are exact references, not aliases; missing references do not fall back
    to other configurations. Failed discovery leaves the previous snapshot intact.
    Credentials remain in source configs or an environment variable containing JSON headers.
    Example: h mcp add search --url https://example.test/mcp --headers-env MCP_HEADERS
    Add/import do not load credential values or connect. --headers-env on add requires --url.
    Stored header-variable references are reused only for the same credential scope.
    Sync may copy active credentials into the target config. Review --dry-run output privately.
    Add --json to listings/discovery/schema commands. --data requires structuredContent or
    exactly one JSON text block. Tool errors exit 1 and preserve the full error result.
    Discovery and test invoke no tools. Calls can mutate data; inspect the schema first.
    Dependencies: the hiiro gem installs mcp (~> 1.5), faraday, and event_stream_parser.
    Wrapper: invoke h-mcp call with separate argv values, --args-file -, and JSON stdin.
    Reference and wrapper examples: docs/h-mcp.md in the hiiro gem.
  TEXT

  def self.run(command, args)
    return puts(GUIDE) if command == 'guide'
    parser = Hiiro::Options.setup do
      option(:config, desc: 'MCP JSON config to read')
      option(:agent, desc: 'select a configured client')
      option(:url, desc: 'explicit Streamable HTTP server URL')
      option(:headers_env, long: 'headers-env', desc: 'environment variable containing JSON HTTP headers')
      option(:timeout, default: '30', desc: 'network request timeout in seconds')
      option(:arguments, long: 'args', desc: 'tool arguments as a JSON object')
      option(:args_file, long: 'args-file', desc: 'tool arguments JSON file, or - for stdin')
      flag(:json, desc: 'machine-readable output')
      flag(:data, desc: 'extract structured data from a call result')
      flag(:all, desc: 'discover enabled registered or selected-config servers')
    end
    tokens = args.dup
    until tokens.empty?
      argument = tokens.shift
      break if argument == '--'
      next unless argument.start_with?('-')
      token = argument.split('=', 2).first
      definition = parser.option_set.definition_for(token)
      raise %(unknown option #{token}; use --help) unless definition
      unless definition.flag? || argument.include?('=')
        raise %(#{token} requires a value) if tokens.empty?
        tokens.shift
      end
    end
    opts = parser.parse(args)
    return puts(opts.help_text) if opts.help?
    raise 'select --config or --agent, not both' if opts[:config] && opts[:agent]
    catalog = MCPCatalog.new(config: opts[:config], agent: opts[:agent])
    name, tool_name = opts.args
    timeout = Float(opts[:timeout])
    raise '--timeout must be positive and finite' unless timeout.positive? && timeout.finite?
    connection_options = { headers_env: opts[:headers_env], timeout: timeout }
    case command
    when 'list', 'ls'
      raise %(usage: h mcp #{command} [--json]) unless opts.args.empty?
      records = catalog.registry
      return puts(JSON.pretty_generate(records)) if opts.json
      print_table(records.map { |server| { name: server['name'], transport: server['transport'], enabled: server['enabled'],
                                          tools: server['tools']&.length, address: server['url'] || server['command'] } })
    when 'info'
      raise 'usage: h mcp info SERVER' unless opts.args.length == 1
      registration = catalog.store.find(name)
      raise %(no registered server #{name}; run: h mcp list) unless registration
      puts JSON.pretty_generate(registration)
    when 'add'
      raise 'usage: h mcp add SERVER --url URL | --config FILE | --agent NAME' unless opts.args.length == 1 && (opts[:url] || opts[:config] || opts[:agent])
      raise '--headers-env on add requires an explicit --url' if opts[:headers_env] && !opts[:url]
      server = catalog.resolve(name, url: opts[:url])
      registration = catalog.register(server, headers_env: opts[:headers_env])
      puts(opts.json ? JSON.pretty_generate(registration) : %(registered #{name}))
    when 'import'
      raise 'usage: h mcp import [--config FILE | --agent NAME]' unless opts.args.empty? && !opts[:url] && !opts[:headers_env]
      servers = catalog.configured
      reject_duplicate_names!(servers)
      catalog.store
      registrations = Hiiro::DB.connection.transaction(mode: :immediate) do
        servers.map { |server| catalog.register(server) }
      end
      return puts(JSON.pretty_generate(registrations)) if opts.json
      print_table(registrations.map { |server| { name: server['name'], transport: server['transport'], enabled: server['enabled'],
                                                address: server['url'] || server['command'] } })
    when 'remove'
      raise 'usage: h mcp remove SERVER' unless opts.args.length == 1
      raise %(no registered server #{name}; run: h mcp list) unless catalog.store.remove(name)
      puts(opts.json ? JSON.pretty_generate('removed' => name) : %(removed #{name}))
    when 'configured'
      raise 'usage: h mcp configured [--config FILE | --agent NAME] [--json]' unless opts.args.empty?
      records = catalog.configured.map { |server| catalog.public_record(server) }
      return puts(JSON.pretty_generate(records)) if opts.json
      print_table(records.map { |server| { name: server['name'], transport: server['transport'], enabled: server['enabled'],
                                          source: server.dig('source', 'path') || server['agent'], address: server['url'] || server['command'] } })
    when 'saved'
      raise 'usage: h mcp saved [--json]' unless opts.args.empty?
      records = catalog.saved
      return puts(JSON.pretty_generate(records)) if opts.json
      print_table(records.map { |server| { name: server['name'], transport: server['transport'], tools: server['tools'].length,
                                          discovered: server['discovered_at'], address: server['url'] || server['command'] } })
    when 'discover'
      raise 'usage: h mcp discover SERVER [--url URL | --config FILE | --agent NAME] or --all [--config FILE | --agent NAME]' unless name || opts.all
      raise 'specify SERVER or --all, not both' if name && opts.all
      raise 'discover accepts one SERVER' if opts.args.length > 1
      raise '--url requires a single SERVER' if opts.all && opts[:url]
      local_bulk = opts.all && !opts[:config] && !opts[:agent]
      servers = if opts.all
        (local_bulk ? catalog.registry : catalog.configured).select { |server| server['enabled'] }
      else
        [catalog.resolve(name, url: opts[:url])]
      end
      reject_duplicate_names!(servers)
      snapshots, errors = [], []
      servers.each do |candidate|
        server_name = candidate.fetch('name')
        begin
          server = local_bulk ? catalog.resolve(server_name) : candidate
          next if opts.all && !server['enabled']
          snapshot = catalog.discover(server, **connection_options)
          snapshots << snapshot
          warn %(saved #{server_name}: #{snapshot['tools'].length} tools) unless opts.json
        rescue StandardError => error
          message = error_message(error)
          errors << { 'name' => server_name, 'error' => message }
          warn %(#{server_name}: #{message})
        end
      end
      puts JSON.pretty_generate(opts.all ? { 'servers' => snapshots, 'errors' => errors } : snapshots.first) if opts.json
      exit 1 unless errors.empty?
    when 'tools', 'tool'
      expected = command == 'tool' ? 2 : 1
      raise %(usage: h mcp #{command} SERVER#{command == 'tool' ? ' TOOL' : ''}) unless opts.args.length == expected
      if command == 'tools'
        tools = catalog.cached(name).fetch('tools')
        return puts(JSON.pretty_generate(tools)) if opts.json
        print_table(tools.map { |tool| { name: tool['name'], description: tool['description'].to_s.gsub(/\s+/, ' ')[0, 160] } })
      else
        tool = catalog.tool(name, tool_name)
        puts JSON.pretty_generate(tool)
        unless opts.json
          puts
          puts 'Call with arguments matching inputSchema:'
          puts %(  h mcp call #{name.shellescape} #{tool_name.shellescape} --args-file -)
          puts 'Full MCP result is JSON. Add --data to extract structuredContent or a single JSON text block.'
        end
      end
    when 'test'
      raise 'usage: h mcp test SERVER [--url URL | --config FILE | --agent NAME] [--json]' unless opts.args.length == 1
      server = catalog.resolve(name, url: opts[:url])
      catalog.connect(server, **connection_options) do |client|
        info = client.server_info
        if opts.json
          puts JSON.pretty_generate(info)
        else
          puts %(OK   #{name}: initialized)
          puts JSON.pretty_generate(info)
        end
      end
    when 'url'
      raise 'usage: h mcp url SERVER [--config FILE | --agent NAME]' unless opts.args.length == 1
      puts catalog.server_url(catalog.resolve(name, url: opts[:url]))
    when 'call'
      raise 'usage: h mcp call SERVER TOOL [--args JSON | --args-file FILE|-] [--data]' unless opts.args.length == 2
      raise 'use --args or --args-file, not both' if opts[:arguments] && opts[:args_file]
      raw = opts[:args_file] ? (opts[:args_file] == '-' ? $stdin.read : File.read(File.expand_path(opts[:args_file]))) : opts[:arguments] || '{}'
      arguments = JSON.parse(raw)
      raise 'tool arguments must be a JSON object' unless arguments.is_a?(Hash)
      server = catalog.resolve(name, url: opts[:url])
      catalog.connect(server, **connection_options) do |client|
        result = client.call_tool(name: tool_name, arguments: arguments).fetch('result')
        if result['isError']
          puts JSON.pretty_generate(result)
          exit 1
        end
        puts JSON.pretty_generate(opts.data ? catalog.data(result) : result)
      end
    else
      raise %(unknown command #{command}; run: h mcp guide)
    end
  rescue StandardError => error
    abort %(h mcp #{command}: #{error_message(error)})
  rescue LoadError => error
    abort %(#{error.class}: install dependencies: gem install mcp -v '~> 1.5' && gem install faraday event_stream_parser)
  end

  def self.reject_duplicate_names!(servers)
    duplicates = servers.group_by { |server| server['name'] }.select { |_, entries| entries.length > 1 }.keys
    raise %(duplicate server names in selected sources: #{duplicates.join(', ')}; select a single --config) unless duplicates.empty?
  end

  def self.error_message(error)
    case error
    when JSON::ParserError then 'invalid JSON; check the input/config/header environment variable'
    when URI::InvalidURIError then 'invalid server URL; check the source configuration'
    when Errno::ENOENT then 'file or executable not found; check the source configuration'
    else
      if error.class.name.start_with?('MCP::', 'Faraday::')
        %(#{error.class}: MCP request failed; check server reachability and authentication)
      else
        error.message
      end
    end
  end

  def self.print_table(rows)
    return puts '(no results)' if rows.empty?
    keys = rows.first.keys
    widths = keys.map { |key| [key.to_s.length, rows.map { |row| row[key].to_s.length }.max].max.clamp(0, 60) }
    header = keys.each_with_index.map { |key, index| key.to_s.ljust(widths[index]) }.join('  ')
    puts header
    puts '-' * header.length
    rows.each do |row|
      puts keys.each_with_index.map { |key, index| row[key].to_s.ljust(widths[index]) }.join('  ')
    end
    puts "(#{rows.length} rows)"
  end
end
