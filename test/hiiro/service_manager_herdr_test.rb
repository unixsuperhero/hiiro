require 'test_helper'

class ServiceManagerHerdrTest < Minitest::Test
  def test_start_records_herdr_location_and_runs_launcher_in_root_pane
    Dir.mktmpdir do |dir|
      config_file = File.join(dir, 'services.yml')
      state_file = File.join(dir, 'running.yml')
      scripts_dir = File.join(dir, 'scripts')
      File.write(config_file, YAML.dump(
        'web' => { 'base_dir' => dir, 'start' => 'bundle exec rackup' },
      ))

      executor = Hiiro::Effects::NullExecutor.new
      executor.stub('tab create', tab_create_json)
      herdr = Hiiro::Herdr.new(executor: executor)
      workspace = Hiiro::Herdr::Workspace.new(
        { 'workspace_id' => 'w1', 'label' => 'development' },
        client: herdr,
      )
      manager = Hiiro::ServiceManager.new(config_file:, state_file:, herdr:)
      manager.define_singleton_method(:scripts_dir) do
        FileUtils.mkdir_p(scripts_dir)
        scripts_dir
      end

      assert manager.start('web', herdr_info: { workspace: }, skip_env: true)

      state = YAML.safe_load_file(state_file).fetch('web')
      assert_equal 'w1', state['herdr_workspace']
      assert_equal 'w1:t3', state['herdr_tab']
      assert_equal 'w1:p3', state['herdr_pane']
      assert_equal [
        'herdr', 'pane', 'run', 'w1:p3', File.join(scripts_dir, 'web.sh'),
      ], executor.calls_to(:run).last[:args]
    end
  end

  private

  def tab_create_json
    JSON.generate('result' => {
      'tab' => { 'tab_id' => 'w1:t3', 'workspace_id' => 'w1' },
      'root_pane' => { 'pane_id' => 'w1:p3', 'workspace_id' => 'w1', 'tab_id' => 'w1:t3' },
    })
  end
end
