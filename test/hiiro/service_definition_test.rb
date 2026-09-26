require "test_helper"

class ServiceDefinitionTest < Minitest::Test
  CONFIG = {
    'base_dir' => 'apps/myapp', 'port' => 3000, 'start' => 'rails s', 'init' => ['bundle install'],
    'env_file' => '.env.development', 'base_env' => 'my-rails.env',
    'env_vars' => { 'GRAPHQL_URL' => { 'variations' => { 'local' => 'http://localhost:4000', 'staging' => 'https://staging' } }, 'PLAIN' => 'x' },
  }.freeze

  def definition(config = CONFIG)
    Hiiro::ServiceDefinition.from_config('my-rails', config, root: '/repo', cwd: '/cwd')
  end

  def test_definition_answers
    d = definition
    assert_equal '/repo/apps/myapp', d.base_directory
    assert_equal '/cwd', definition({}).base_directory
    assert_equal 'localhost', d.host
    assert_equal 'http://localhost:3000', d.url
    assert_nil definition({}).url
    assert_equal ['bundle install'], d.init_commands
    assert_equal 'rails s', d.start_command
    refute d.group?
  end

  def test_environment_file_from_legacy_and_list_shapes
    ef = definition.environment_files.first
    assert_equal '/repo/apps/myapp/.env.development', ef.destination_path
    assert_equal File.join(Hiiro::ServiceManager::ENV_TEMPLATES_DIR, 'my-rails.env'), ef.template_path
    assert_equal({ 'GRAPHQL_URL' => { 'local' => 'http://localhost:4000', 'staging' => 'https://staging' } }, ef.variables)
    assert_equal 'local', ef.selected_variation('GRAPHQL_URL', {})
    assert_equal 'staging', ef.selected_variation('GRAPHQL_URL', 'GRAPHQL_URL' => 'staging')
    assert_equal({ 'GRAPHQL_URL' => 'https://staging' }, ef.effective_values(GRAPHQL_URL: 'staging'))
    assert_equal({}, ef.effective_values('GRAPHQL_URL' => 'nope'))

    listed = definition('env_files' => [{ 'env_file' => '.env' }, { env_file: '.env.test' }])
    assert_equal ['.env', '.env.test'], listed.environment_files.map { |e| e.spec[:env_file] }
    assert_equal [], definition({}).environment_files
  end

  def test_desired_content_replaces_or_appends
    ef = definition.environment_files.first
    lines = ef.desired_content(["A=1\n", "GRAPHQL_URL=old\n"], {})
    assert_equal ["A=1\n", "GRAPHQL_URL=http://localhost:4000\n"], lines
    assert_equal ["GRAPHQL_URL=https://staging\n"], ef.desired_content([], 'GRAPHQL_URL' => 'staging')
  end

  def test_service_group
    group = Hiiro::ServiceGroup.from_config('stack', 'services' => [{ 'name' => 'a', 'use' => { 'X' => 'staging' } }, { name: 'b' }, 'junk'])
    assert group.group?
    assert_equal %w[a b], group.service_names
    assert_equal({ 'X' => 'staging' }, group.overrides_for('a'))
    assert_equal({}, group.overrides_for('b'))
    assert Hiiro::ServiceGroup.group_config?('services' => [])
    refute Hiiro::ServiceGroup.group_config?('start' => 'x')
  end
end
