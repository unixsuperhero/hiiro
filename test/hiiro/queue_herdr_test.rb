require 'test_helper'

class QueueHerdrTest < Minitest::Test
  def test_launch_task_records_herdr_location_and_runs_launcher_in_root_pane
    Dir.mktmpdir do |dir|
      queue_dirs = Hiiro::Queue::STATUSES.to_h do |status|
        [status.to_sym, FileUtils.mkdir_p(File.join(dir, status)).first]
      end
      File.write(File.join(queue_dirs[:pending], 'review.md'), "Review the change\n")

      executor = Hiiro::Effects::NullExecutor.new
      executor.stub('workspace list', workspace_list_json)
      executor.stub('tab create', tab_create_json)
      herdr = Hiiro::Herdr.new(executor: executor)
      hiiro = Struct.new(:herdr_client).new(herdr)
      queue = Hiiro::Queue.new(hiiro)
      queue.instance_variable_set(:@queue_dirs, queue_dirs)

      queue.launch_task('review')

      meta = YAML.safe_load_file(File.join(queue_dirs[:running], 'review.meta'))
      assert_equal 'w1', meta['herdr_workspace']
      assert_equal 'w1:t2', meta['herdr_tab']
      assert_equal 'w1:p2', meta['herdr_pane']
      assert_equal [
        'herdr', 'pane', 'run', 'w1:p2',
        File.join(queue_dirs[:running], 'review.sh'),
      ], executor.calls_to(:run).last[:args]
    end
  end

  private

  def workspace_list_json
    JSON.generate('result' => {
      'workspaces' => [{
        'workspace_id' => 'w1', 'number' => 1, 'label' => 'hq',
        'focused' => false, 'pane_count' => 1, 'tab_count' => 1,
      }],
    })
  end

  def tab_create_json
    JSON.generate('result' => {
      'tab' => { 'tab_id' => 'w1:t2', 'workspace_id' => 'w1' },
      'root_pane' => { 'pane_id' => 'w1:p2', 'workspace_id' => 'w1', 'tab_id' => 'w1:t2' },
    })
  end
end
