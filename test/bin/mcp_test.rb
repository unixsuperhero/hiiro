# frozen_string_literal: true

require_relative '../test_helper'
require 'socket'
require 'json'
require 'open3'
require 'rbconfig'
require 'digest'
require 'hiiro/mcp'

class MCPCommandTest < Minitest::Test
  BIN = File.expand_path('../../bin/h-mcp', __dir__)
  LIB = File.expand_path('../../lib', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('h-mcp-test-'))
    @home = File.join(@root, 'home')
    @db = File.join(@root, 'hiiro.db')
    @legacy = File.join(@root, 'legacy')
    @path = File.join(@root, 'path')
    FileUtils.mkdir_p([@home, @legacy, @path])
    # Only ruby is reachable: inventory runs `codex` from PATH, and no real client may run.
    File.symlink(RbConfig.ruby, File.join(@path, 'ruby'))
    @listener = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@listener.addr[1]}/mcp"
    @config = File.join(@root, 'mcp.json')
    @requests = []
    @cursor = 'opaque /?+== cursor'
    @sse = @cycle = @empty_tools = false
    write_config('test-search' => { 'url' => @url, 'headers' => { 'Authorization' => '${env:MCP_TEST_TOKEN}' } })
    @thread = Thread.new do
      loop do
        socket = @listener.accept
        begin
          serve(socket)
        ensure
          socket.close
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
  end

  def teardown
    stop_server
    FileUtils.remove_entry(@root)
  end

  def stop_server
    @listener.close unless @listener.closed?
    @thread.kill
    @thread.join
  end

  def write_config(servers, options = {})
    path = options.fetch(:path, @config)
    key = options.fetch(:key, 'mcpServers')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(key => servers))
    path
  end

  def serve(socket)
    line = socket.gets
    return unless line
    method, path = line.split(' ')
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      key, value = line.split(':', 2)
      headers[key.downcase] = value.strip
    end
    body = socket.read(headers.fetch('content-length', '0').to_i)
    request = body.empty? ? {} : JSON.parse(body)
    @requests << { 'path' => path, 'authorization' => headers['authorization'],
                   'rpc' => request['method'], 'cursor' => request.dig('params', 'cursor') }
    response = { 'jsonrpc' => '2.0', 'id' => request['id'] }
    case request['method']
    when 'initialize'
      response['result'] = {
        'protocolVersion' => request.dig('params', 'protocolVersion'),
        'capabilities' => { 'tools' => {} },
        'serverInfo' => { 'name' => 'test-search', 'version' => '1' },
        'instructions' => 'Search only the supplied channel.'
      }
    when 'tools/list'
      if @empty_tools
        response['result'] = { 'tools' => [] }
      elsif request.dig('params', 'cursor')
        response['result'] = { 'tools' => [{
          'name' => 'find_messages', 'description' => 'Search messages by channel and text.',
          'inputSchema' => { 'type' => 'object', 'properties' => {
            'channel' => { 'type' => 'string' }, 'query' => { 'type' => 'string' }
          }, 'required' => %w[channel query] },
          'outputSchema' => { 'type' => 'object', 'required' => ['matches'] },
          'annotations' => { 'readOnlyHint' => true }
        }] }
        response['result']['nextCursor'] = @cursor if @cycle
      else
        response['result'] = { 'tools' => [], 'nextCursor' => @cursor }
      end
    when 'tools/call'
      arguments = request.fetch('params').fetch('arguments')
      if !arguments.key?('channel') || !arguments.key?('query')
        response['result'] = { 'isError' => true, 'content' => [{ 'type' => 'text', 'text' => 'channel and query required' }] }
      else
        messages = [
          { 'id' => 'm1', 'channel' => 'engineering', 'text' => 'deployment completed' },
          { 'id' => 'm2', 'channel' => 'support', 'text' => 'deployment delayed' },
          { 'id' => 'm3', 'channel' => 'engineering', 'text' => 'meeting tomorrow' }
        ]
        matches = messages.select { |message| message['channel'] == arguments['channel'] && message['text'].include?(arguments['query']) }
        response['result'] = { 'isError' => false, 'structuredContent' => { 'matches' => matches },
                               'content' => [{ 'type' => 'text', 'text' => 'Search complete.' }] }
      end
    end
    status = if method == 'DELETE'
      '204 No Content'
    elsif method == 'GET'
      '405 Method Not Allowed'
    elsif response.key?('result')
      '200 OK'
    else
      '202 Accepted'
    end
    payload = response.key?('result') ? JSON.generate(response) : ''
    content_type = 'application/json'
    if @sse && response.key?('result')
      payload = "event: message\ndata: #{payload}\n\n"
      content_type = 'text/event-stream'
    end
    socket.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
  end

  def environment(token: 'sentinel-secret')
    { 'HOME' => @home, 'PATH' => "#{@path}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'XDG_CONFIG_HOME' => File.join(@home, '.config'),
      'XDG_DATA_HOME' => File.join(@home, '.local', 'share'),
      'CODEX_HOME' => File.join(@home, '.codex'),
      'HIIRO_TEST_DB' => "sqlite://#{@db}", 'MCP_TEST_LEGACY' => @legacy,
      'MCP_TEST_TOKEN' => token,
      'MCP_TEST_HEADERS' => token && JSON.generate('Authorization' => token) }
  end

  def cli(*args, input: '', token: 'sentinel-secret', env: {})
    Open3.capture3(environment(token: token).merge(env), RbConfig.ruby, '-I', LIB, BIN, *args,
                   stdin_data: input, chdir: @root, unsetenv_others: true)
  end

  def succeed(*args, **options)
    stdout, stderr, status = cli(*args, **options)
    assert status.success?, "#{args.join(' ')} failed:\n#{stderr}\n#{stdout}"
    stdout
  end

  def json_cli(*args, **options)
    JSON.parse(succeed(*args, **options))
  end

  def fail_command(*args, **options)
    stdout, stderr, status = cli(*args, **options)
    refute status.success?, "#{args.join(' ')} unexpectedly succeeded:\n#{stdout}"
    [stdout, stderr]
  end

  def ruby_json(source)
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, '-I', LIB, '-rhiiro/mcp', '-e', source,
                                            chdir: @root, unsetenv_others: true)
    assert status.success?, "registry scenario failed:\n#{stderr}\n#{stdout}"
    JSON.parse(stdout)
  end

  def records
    json_cli('list', '--json')
  end

  def info(name = 'test-search')
    json_cli('info', name)
  end

  def discover(*args)
    args = ['--config', @config] if args.empty?
    json_cli('discover', 'test-search', *args, '--json')
  end

  def call_search(*args, token: 'sentinel-secret')
    json_cli('call', 'test-search', 'find_messages', *args, '--args',
             '{"channel":"engineering","query":"deployment"}', '--data', token: token)
  end

  def assert_search(result)
    assert_equal({ 'matches' => [{ 'id' => 'm1', 'channel' => 'engineering', 'text' => 'deployment completed' }] }, result)
  end

  def rpc_requests(method)
    @requests.select { |request| request['rpc'] == method }
  end

  def test_paginated_sse_discovery_schema_rotated_auth_and_offline_catalog
    @sse = true
    snapshot = discover
    assert_equal ['find_messages'], snapshot.fetch('tools').map { |tool| tool['name'] }
    assert_equal 'Search only the supplied channel.', snapshot.dig('initialize', 'instructions')
    assert_equal [nil, 'opaque /?+== cursor'], rpc_requests('tools/list').map { |request| request['cursor'] }
    assert_equal [], rpc_requests('tools/call')
    stored = ruby_json("puts JSON.generate(Hiiro::DB.connection[:mcps].select_map(:record_json))")
    assert_equal ['test-search'], stored.map { |bytes| JSON.parse(bytes).fetch('name') }
    refute_includes stored.join, 'sentinel-secret'
    refute JSON.parse(stored.fetch(0)).key?('connection')
    schema = json_cli('tool', 'test-search', 'find_messages', '--json', token: nil)
    assert_equal %w[channel query], schema.dig('inputSchema', 'required')
    assert_equal ['matches'], schema.dig('outputSchema', 'required')
    assert_equal true, schema.dig('annotations', 'readOnlyHint')
    assert_search(json_cli('call', 'test-search', 'find_messages', '--args-file', '-', '--data',
                           input: '{"channel":"engineering","query":"deployment"}', token: 'rotated-secret'))
    assert_equal 'rotated-secret', rpc_requests('tools/call').last['authorization']
    stop_server
    assert_equal ['test-search'], json_cli('saved', '--json', token: nil).map { |server| server['name'] }
    assert_equal ['find_messages'], json_cli('tools', 'test-search', '--json', token: nil).map { |tool| tool['name'] }
    assert_equal 'test-search', json_cli('info', 'test-search', token: nil).fetch('name')
  end

  def test_empty_opaque_cursor_and_zero_tool_catalog
    @cursor = ''
    assert_equal ['find_messages'], discover.fetch('tools').map { |tool| tool['name'] }
    assert_equal [nil, ''], rpc_requests('tools/list').map { |request| request['cursor'] }
    @empty_tools = true
    assert_equal [], discover.fetch('tools')
    stop_server
    saved = json_cli('saved', '--json', token: nil)
    assert_equal ['test-search'], saved.map { |server| server['name'] }
    assert_equal [], saved.first.fetch('tools')
    assert_equal [], json_cli('tools', 'test-search', '--json', token: nil)
  end

  def test_failed_refresh_keeps_previous_catalog_and_tool_errors_exit_nonzero
    discover
    before = info
    @cycle = true
    fail_command('discover', 'test-search', '--config', @config)
    assert_equal before, info
    stdout, = fail_command('call', 'test-search', 'find_messages', '--args', '{}', '--data')
    assert_equal({ 'isError' => true, 'content' => [{ 'type' => 'text', 'text' => 'channel and query required' }] }, JSON.parse(stdout))
  end

  def test_data_preserves_json_values_and_rejects_ambiguous_text
    catalog = MCPCatalog.new
    assert_equal({ 'count' => 0 }, catalog.data('structuredContent' => { 'count' => 0 }, 'content' => []))
    assert_equal false, catalog.data('structuredContent' => false, 'content' => [])
    assert_nil catalog.data('structuredContent' => nil, 'content' => [])
    assert_equal ['m1'], catalog.data('content' => [{ 'type' => 'text', 'text' => '["m1"]' }])
    assert_raises(RuntimeError) { catalog.data('content' => [{ 'type' => 'text', 'text' => 'No messages.' }]) }
    assert_raises(RuntimeError) { catalog.data('content' => [{ 'type' => 'text', 'text' => '{}' }, { 'type' => 'text', 'text' => '{}' }]) }
  end

  def test_persistent_local_crud_and_call_without_discovery
    succeed('add', 'test-search', '--config', @config, token: nil)
    registered = info
    assert_equal @url, registered.fetch('url')
    assert_equal @config, registered.dig('source', 'path')
    assert_equal 'test-search', registered.dig('source', 'name')
    refute registered.key?('discovered_at')
    assert_equal [], @requests
    assert_search(call_search(token: 'first-call-secret'))
    assert_equal 'first-call-secret', rpc_requests('tools/call').last['authorization']
    assert_equal [], json_cli('saved', '--json')
    write_config('test-search' => { 'url' => @url }, 'disabled' => { 'url' => @url, 'disabled' => true })
    original = File.read(@config)
    succeed('import', '--config', @config, token: nil)
    assert_equal %w[disabled test-search], records.map { |server| server['name'] }
    assert_equal false, info('disabled').fetch('enabled')
    assert_equal original, File.read(@config)
    discover
    succeed('remove', 'test-search')
    assert_equal ['disabled'], records.map { |server| server['name'] }
    assert_equal [], json_cli('saved', '--json')
    fail_command('info', 'test-search')
    fail_command('tool', 'test-search', 'find_messages', '--json')
    fail_command('call', 'test-search', 'find_messages', '--args', '{}')
    assert_search(call_search('--config', @config))
  end

  def test_local_precedence_explicit_override_and_missing_source_do_not_fall_back
    other = File.join(@root, '.cursor', 'mcp.json')
    write_config({ 'test-search' => { 'url' => @url + '/other' } }, path: other)
    fail_command('call', 'test-search', 'find_messages', '--args', '{}')
    fail_command('add', 'alias', '--config', @config)
    assert_equal [], @requests
    succeed('add', 'test-search', '--config', @config)
    assert_search(call_search)
    assert_equal '/mcp', rpc_requests('tools/call').last['path']
    assert_search(call_search('--config', other))
    assert_equal '/mcp/other', rpc_requests('tools/call').last['path']
    assert_nil rpc_requests('tools/call').last['authorization']
    File.delete(@config)
    before = @requests.dup
    fail_command('call', 'test-search', 'find_messages', '--args', '{}')
    assert_equal before, @requests
    assert_search(call_search('--url', @url + '/explicit'))
    assert_equal '/mcp/explicit', rpc_requests('tools/call').last['path']
    assert_nil rpc_requests('tools/call').last['authorization']
    assert_equal @config, info.dig('source', 'path')
  end

  def test_reimport_preserves_catalog_but_source_or_destination_change_invalidates_it
    discover
    before = info
    succeed('import', '--config', @config, token: nil)
    assert_equal before.fetch('tools'), info.fetch('tools')
    assert_equal before.fetch('discovered_at'), info.fetch('discovered_at')
    other = File.join(@root, 'same-url.json')
    write_config({ 'test-search' => { 'url' => @url } }, path: other)
    succeed('add', 'test-search', '--config', other)
    assert_equal other, info.dig('source', 'path')
    assert_equal before.fetch('created_at'), info.fetch('created_at')
    fail_command('tools', 'test-search', '--json')
    discover('--config', other)
    write_config({ 'test-search' => { 'url' => @url + '/changed' } }, path: other)
    succeed('add', 'test-search', '--config', other)
    assert_equal @url + '/changed', info.fetch('url')
    assert_equal [], json_cli('saved', '--json')
    fail_command('tools', 'test-search', '--json')
    assert_search(call_search)
    assert_equal '/mcp/changed', rpc_requests('tools/call').last['path']
  end

  def test_batch_continues_after_missing_source_and_skips_disabled_servers
    succeed('add', 'test-search', '--url', @url)
    broken = File.join(@root, 'broken.json')
    write_config({ 'broken' => { 'url' => @url + '/broken' } }, path: broken)
    succeed('add', 'broken', '--config', broken)
    File.delete(broken)
    write_config('disabled' => { 'url' => @url + '/disabled', 'disabled' => true })
    succeed('add', 'disabled', '--config', @config)
    stdout, = fail_command('discover', '--all', '--json')
    result = JSON.parse(stdout)
    assert_equal ['test-search'], result.fetch('servers').map { |server| server['name'] }
    assert_equal [['find_messages']], result.fetch('servers').map { |server| server.fetch('tools').map { |tool| tool['name'] } }
    assert_equal ['broken'], result.fetch('errors').map { |error| error['name'] }
    refute @requests.any? { |request| request['path'] == '/mcp/disabled' }
    fail_command('test', 'disabled')
  end

  def test_header_environment_reference_is_private_current_and_destination_scoped
    succeed('add', 'test-search', '--url', @url, '--headers-env', 'MCP_TEST_HEADERS', token: nil)
    assert_equal 'MCP_TEST_HEADERS', info.fetch('headers_env')
    assert_equal [], @requests
    stdout, stderr = fail_command('test', 'test-search', env: { 'MCP_TEST_HEADERS' => '["sentinel-secret"]' })
    refute_includes stdout + stderr, 'sentinel-secret'
    assert_equal [], @requests
    assert_search(call_search(token: 'rotated-secret'))
    assert_equal 'rotated-secret', rpc_requests('tools/call').last['authorization']
    succeed('add', 'test-search', '--url', @url, token: nil)
    assert_equal 'MCP_TEST_HEADERS', info.fetch('headers_env')
    assert_search(call_search('--url', @url + '/other'))
    assert_nil rpc_requests('tools/call').last['authorization']
    succeed('add', 'test-search', '--url', @url + '/changed', token: nil)
    assert_search(call_search)
    assert_nil rpc_requests('tools/call').last['authorization']
    bytes = ruby_json("puts JSON.generate(Hiiro::DB.connection[:mcps].select_map(:record_json))").join
    refute_includes bytes, 'sentinel-secret'
    refute_includes bytes, 'rotated-secret'
  end

  def test_inventory_and_registration_do_not_persist_source_credentials
    write_config({
      'local' => { 'command' => ['ruby', '--token', 'sentinel-secret'], 'environment' => { 'TOKEN' => 'sentinel-secret' } },
      'private-http' => { 'url' => @url + '?token=sentinel-secret', 'headers' => { 'Authorization' => 'sentinel-secret' } }
    }, key: 'mcp')
    inventory = json_cli('configured', '--config', @config, '--json')
    assert_equal 'ruby', inventory.find { |server| server['name'] == 'local' }.fetch('command')
    assert_equal ['TOKEN'], inventory.find { |server| server['name'] == 'local' }.fetch('env_names')
    assert_equal @url, inventory.find { |server| server['name'] == 'private-http' }.fetch('url')
    succeed('import', '--config', @config)
    assert_equal %w[local private-http], records.map { |server| server['name'] }
    bytes = ruby_json("puts JSON.generate(Hiiro::DB.connection[:mcps].select_map(:record_json))").join
    refute_includes JSON.generate(inventory) + JSON.generate(records) + bytes, 'sentinel-secret'
    write_config('bad' => { 'url' => 'http://user:sentinel-secret@invalid host/mcp' })
    stdout, stderr = fail_command('discover', 'bad', '--config', @config)
    refute_includes stdout + stderr, 'sentinel-secret'
  end

  def legacy_record(name: 'test-search')
    source = { 'kind' => 'registry', 'url' => @url }
    { 'name' => name, 'transport' => 'http', 'source' => source, 'enabled' => true, 'url' => @url,
      'discovered_at' => '2026-10-01T12:00:00Z', 'initialize' => { 'instructions' => 'Migrated instructions.' },
      'tools' => [{ 'name' => 'find_messages', 'inputSchema' => { 'type' => 'object' } }],
      'custom_metadata' => { 'owner' => 'engineering' }, 'headers_env' => 'MCP_TEST_HEADERS',
      'credential_scope' => Digest::SHA256.hexdigest(JSON.generate([source, { 'url' => @url }])) }
  end

  def migrate
    ruby_json(<<~'RUBY')
      begin
        result = { 'records' => MCPRegistry.new(legacy_dir: ENV.fetch('MCP_TEST_LEGACY')).all }
      rescue StandardError => error
        result = { 'error' => error.class.name }
      end
      result['names'] = Hiiro::DB.connection[:mcps].order(:name).select_map(:name)
      puts JSON.generate(result)
    RUBY
  end

  def test_legacy_migration_is_atomic_preserves_metadata_auth_and_never_resurrects
    succeed('add', 'current', '--url', @url + '/newer')
    current = info('current')
    record = legacy_record
    path = File.join(@legacy, 'a-valid.json')
    original = JSON.generate(record)
    File.write(path, original)
    File.write(File.join(@legacy, 'current.json'), JSON.generate(legacy_record(name: 'current')))
    invalid = File.join(@legacy, 'z-invalid.json')
    File.write(invalid, '{broken json')
    failed = migrate
    assert_equal 'ArgumentError', failed.fetch('error')
    assert_equal ['current'], failed.fetch('names')
    File.delete(invalid)
    assert_equal %w[current test-search], migrate.fetch('names')
    assert_equal current, info('current')
    migrated = info
    %w[source tools initialize headers_env credential_scope discovered_at custom_metadata].each do |field|
      assert_equal record.fetch(field), migrated.fetch(field)
    end
    assert_equal original, File.read(path)
    assert_equal [], @requests
    assert_equal ['find_messages'], json_cli('tools', 'test-search', '--json', token: nil).map { |tool| tool['name'] }
    assert_search(call_search(token: 'migrated-secret'))
    assert_equal 'migrated-secret', rpc_requests('tools/call').last['authorization']
    succeed('remove', 'test-search')
    assert_equal ['current'], migrate.fetch('names')
    assert_equal original, File.read(path)
  end

  def test_empty_legacy_migration_is_once_only
    assert_equal [], migrate.fetch('names')
    File.write(File.join(@legacy, 'late.json'), JSON.generate(legacy_record))
    assert_equal [], migrate.fetch('names')
    succeed('add', 'current', '--url', @url)
    assert_equal ['current'], records.map { |server| server['name'] }
  end

  def test_http_sync_dry_run_and_explicit_credential_export_preserve_manual_settings
    succeed('add', 'test-search', '--url', @url, '--headers-env', 'MCP_TEST_HEADERS', token: nil)
    target = File.join(@root, '.cursor', 'mcp.json')
    write_config({ 'manual' => { 'command' => 'manual-server', 'args' => ['--keep'] } }, path: target)
    data = JSON.parse(File.read(target)).merge('editor' => { 'theme' => 'dark' })
    File.write(target, JSON.generate(data))
    before = File.read(target)
    succeed('sync', 'cursor', '--project', '--dry-run')
    assert_equal before, File.read(target)
    succeed('sync', 'cursor', '--project')
    exported = JSON.parse(File.read(target))
    assert_equal({ 'theme' => 'dark' }, exported.fetch('editor'))
    assert_equal({ 'command' => 'manual-server', 'args' => ['--keep'] }, exported.dig('mcpServers', 'manual'))
    assert_equal @url, exported.dig('mcpServers', 'test-search', 'url')
    assert_equal({ 'Authorization' => 'sentinel-secret' }, exported.dig('mcpServers', 'test-search', 'headers'))
    assert_equal [], @requests
  end

  def test_prune_removes_only_unchanged_owned_exports
    succeed('add', 'a-owned', '--url', @url + '/a')
    succeed('add', 'b-edited', '--url', @url + '/b')
    target = File.join(@root, '.cursor', 'mcp.json')
    write_config({ 'manual' => { 'url' => @url + '/a' } }, path: target)
    succeed('sync', 'cursor', '--project')
    exported = JSON.parse(File.read(target))
    exported.fetch('mcpServers').fetch('b-edited')['url'] = @url + '/user-edit'
    File.write(target, JSON.generate(exported))
    succeed('remove', 'a-owned')
    succeed('remove', 'b-edited')
    succeed('sync', 'cursor', '--project')
    assert_equal %w[a-owned b-edited manual], JSON.parse(File.read(target)).fetch('mcpServers').keys.sort
    succeed('sync', 'cursor', '--project', '--prune')
    remaining = JSON.parse(File.read(target)).fetch('mcpServers')
    assert_equal %w[b-edited manual], remaining.keys.sort
    assert_equal @url + '/user-edit', remaining.dig('b-edited', 'url')
    assert_equal({ 'url' => @url + '/a' }, remaining.fetch('manual'))
  end

  def test_unsupported_sync_connections_fail_before_writing
    succeed('add', 'test-search', '--url', @url, '--headers-env', 'MCP_TEST_HEADERS', token: nil)
    codex = File.join(@root, '.codex', 'config.toml')
    FileUtils.mkdir_p(File.dirname(codex))
    File.write(codex, "model = \"keep-me\"\n")
    fail_command('sync', 'codex', '--project')
    assert_equal "model = \"keep-me\"\n", File.read(codex)
    write_config('local' => { 'command' => 'never-executed' })
    succeed('add', 'local', '--config', @config, token: nil)
    target = File.join(@root, '.cursor', 'mcp.json')
    write_config({ 'manual' => { 'url' => @url + '/manual' } }, path: target)
    before = File.read(target)
    fail_command('sync', 'cursor', '--project')
    assert_equal before, File.read(target)
    assert_equal [], @requests
  end

  STDIO_SERVER = <<~'FIXTURE'
    require 'json'
    $stdout.sync = true
    $stdin.each_line do |line|
      request = JSON.parse(line)
      next unless request.key?('id')
      response = { 'jsonrpc' => '2.0', 'id' => request['id'] }
      case request['method']
      when 'initialize'
        response['result'] = { 'protocolVersion' => request.dig('params', 'protocolVersion'), 'capabilities' => { 'tools' => {} },
                               'serverInfo' => { 'name' => 'stdio-fixture', 'version' => '1' } }
      when 'tools/list'
        response['result'] = { 'tools' => [{ 'name' => 'where', 'description' => 'Report the working directory and greeting.',
                                             'inputSchema' => { 'type' => 'object', 'properties' => { 'text' => { 'type' => 'string' } }, 'required' => ['text'] },
                                             'annotations' => { 'readOnlyHint' => true } }] }
      when 'tools/call'
        text = request.dig('params', 'arguments', 'text')
        response['result'] = { 'isError' => false, 'content' => [{ 'type' => 'text', 'text' => 'ok' }],
                                'structuredContent' => { 'cwd' => Dir.pwd, 'greeting' => ENV['FIXTURE_GREETING'], 'echo' => text } }
      else
        response['error'] = { 'code' => -32601, 'message' => 'method not found' }
      end
      puts JSON.generate(response)
    end
  FIXTURE

  def mcp_sync_state(path)
    ruby_json("puts JSON.generate(MCPRegistry.new.sync_state(#{path.inspect}))")
  end

  def test_packaged_library_resolves_client_targets_without_the_command_file
    write_config({ 'project-search' => { 'url' => @url } }, path: File.join(@root, '.cursor', 'mcp.json'))
    loaded = ruby_json(<<~'RUBY')
      servers = MCPCatalog.new(agent: 'cursor').configured.map { |server| [server['name'], server.dig('source', 'path')] }
      features = $LOADED_FEATURES.grep(/mcp/).grep_v(%r{/gems/})
      puts JSON.generate('servers' => servers, 'features' => features)
    RUBY
    assert_equal [['project-search', File.join(@root, '.cursor', 'mcp.json')]], loaded.fetch('servers')
    assert_equal %w[mcp.rb mcp/catalog.rb mcp/registry.rb mcp/sync.rb].map { |file| File.join(LIB, 'hiiro', file) },
                 loaded.fetch('features').sort
  end

  def test_stdio_source_discovers_schemas_and_calls_in_its_saved_directory
    script = File.join(@root, 'stdio_server.rb')
    File.write(script, STDIO_SERVER)
    FileUtils.mkdir_p(File.join(@root, 'work'))
    write_config('local' => { 'command' => 'ruby', 'args' => [script], 'cwd' => 'work',
                              'env' => { 'FIXTURE_GREETING' => '${env:MCP_TEST_GREETING}' } })
    succeed('add', 'local', '--config', @config)
    registered = info('local')
    assert_equal ['stdio', 'ruby', ['FIXTURE_GREETING']], registered.values_at('transport', 'command', 'env_names')
    refute registered.key?('args')
    snapshot = json_cli('discover', 'local', '--json', env: { 'MCP_TEST_GREETING' => 'hello' })
    assert_equal [{ 'name' => 'where', 'description' => 'Report the working directory and greeting.',
                    'inputSchema' => { 'type' => 'object', 'properties' => { 'text' => { 'type' => 'string' } }, 'required' => ['text'] },
                    'annotations' => { 'readOnlyHint' => true } }], snapshot.fetch('tools')
    result = json_cli('call', 'local', 'where', '--args-file', '-', '--data', input: '{"text":"hi"}',
                      env: { 'MCP_TEST_GREETING' => 'hello' })
    assert_equal({ 'cwd' => File.join(@root, 'work'), 'greeting' => 'hello', 'echo' => 'hi' }, result)
    _, stderr = fail_command('url', 'local')
    assert_equal "h mcp url: local uses stdio and has no HTTP URL\n", stderr
    assert_equal [], @requests
  end

  def test_codex_sync_edits_url_blocks_in_place_and_rejects_unsupported_shapes
    succeed('add', 'a-search', '--url', @url + '/a')
    succeed('add', 'b-new', '--url', @url + '/b')
    codex = File.join(@root, '.codex', 'config.toml')
    FileUtils.mkdir_p(File.dirname(codex))
    File.write(codex, <<~TOML)
      # user settings
      model = "keep-me"

      [mcp_servers.a-search]
      # exported by hand
      url = "http://old.invalid/mcp" # trailing comment

      [profiles.work]
      approval = "never"
    TOML
    succeed('sync', 'codex', '--project')
    assert_equal <<~TOML, File.read(codex)
      # user settings
      model = "keep-me"

      [mcp_servers.a-search]
      # exported by hand
      url = "#{@url}/a" # trailing comment

      [profiles.work]
      approval = "never"
      [mcp_servers.b-new]
      url = "#{@url}/b"
    TOML
    assert_equal %w[a-search b-new], mcp_sync_state(codex).keys
    ownership = mcp_sync_state(codex)
    backups = Dir.glob("#{codex}.bak-*")
    [
      "[mcp_servers.a-search]\ncommand = \"never-run\"\n",
      "mcp_servers = { a-search = { url = \"#{@url}/a\" } }\n",
      "[mcp_servers.a-search]\nurl = \"\"\"\n#{@url}/a\n\"\"\"\n",
      "[mcp_servers.a-search.env]\nTOKEN = \"x\"\n"
    ].each do |unsupported|
      File.write(codex, unsupported)
      fail_command('sync', 'codex', '--project')
      assert_equal unsupported, File.read(codex)
      assert_equal ownership, mcp_sync_state(codex)
    end
    assert_equal backups, Dir.glob("#{codex}.bak-*")
  end

  def test_dry_run_and_rejected_exports_keep_config_and_ownership
    succeed('add', 'test-search', '--url', @url)
    target = File.join(@root, '.cursor', 'mcp.json')
    write_config({ 'manual' => { 'url' => @url + '/manual' } }, path: target)
    before = File.read(target)
    stdout = succeed('sync', 'cursor', '--project', '--dry-run')
    assert_equal "[dry-run] #{target}", stdout.lines.first.chomp
    assert_equal before, File.read(target)
    assert_equal({}, mcp_sync_state(target))
    succeed('sync', 'cursor', '--project')
    ownership = mcp_sync_state(target)
    assert_equal ['test-search'], ownership.keys
    exported = File.read(target)
    write_config('local' => { 'command' => 'never-executed' })
    succeed('add', 'local', '--config', @config)
    fail_command('sync', 'cursor', '--project')
    assert_equal exported, File.read(target)
    assert_equal ownership, mcp_sync_state(target)
  end

  def test_same_name_export_overwrites_and_replaces_through_a_symlink_with_a_private_backup
    succeed('add', 'test-search', '--url', @url)
    real = File.join(@root, 'real', 'mcp.json')
    write_config({ 'test-search' => { 'command' => 'manual-server' }, 'manual' => { 'url' => @url + '/manual' } }, path: real)
    original = File.read(real)
    target = File.join(@root, '.cursor', 'mcp.json')
    FileUtils.mkdir_p(File.dirname(target))
    File.symlink(real, target)
    succeed('sync', 'cursor', '--project')
    assert File.symlink?(target)
    assert_equal({ 'test-search' => { 'url' => @url }, 'manual' => { 'url' => @url + '/manual' } },
                 JSON.parse(File.read(real)).fetch('mcpServers'))
    backups = Dir.glob("#{target}.bak-*")
    assert_equal 1, backups.length
    assert_equal original, File.read(backups.first)
    assert_equal 0o600, File.stat(backups.first).mode & 0o777
  end

  def test_config_replacement_precedes_the_separate_ownership_save
    target = write_config({ 'manual' => { 'url' => @url + '/manual' } }, path: File.join(@root, 'sequential.json'))
    store = Object.new
    def store.sync_state(_path) = {}
    def store.save_sync_state(_path, _state) = raise('ownership save failed')
    opts = OpenStruct.new(prune: false, dry_run: false)
    error = assert_raises(RuntimeError) do
      capture_io do
        MCPSync.sync_json(path: target, container_keys: ['mcpServers'], servers: { 'test-search' => { 'url' => @url } },
                          store: store, opts: opts)
      end
    end
    assert_equal 'ownership save failed', error.message
    assert_equal({ 'manual' => { 'url' => @url + '/manual' }, 'test-search' => { 'url' => @url } },
                 JSON.parse(File.read(target)).fetch('mcpServers'))
  end

  def test_canonical_export_and_restore_carry_registrations_catalogs_and_sync_ownership
    discover
    target = File.join(@root, '.cursor', 'mcp.json')
    write_config({}, path: target)
    succeed('add', 'plain', '--url', @url + '/plain')
    succeed('sync', 'cursor', '--project')
    export = File.join(@root, 'export.json')
    db_cli = ->(db, *args) { Open3.capture3(environment.merge('HIIRO_TEST_DB' => "sqlite://#{db}"), RbConfig.ruby, '-I', LIB,
                                            File.expand_path('../../bin/h-db', __dir__), *args, chdir: @root, unsetenv_others: true) }
    _, stderr, status = db_cli.call(@db, 'export', export)
    assert status.success?, stderr
    before = [records, mcp_sync_state(target)]
    @db = File.join(@root, 'restored.db')
    _, stderr, status = db_cli.call(@db, 'restore', export)
    assert status.success?, stderr
    assert_equal before, [records, mcp_sync_state(target)]
    stop_server
    assert_equal ['find_messages'], json_cli('tools', 'test-search', '--json', token: nil).map { |tool| tool['name'] }
  end
end
