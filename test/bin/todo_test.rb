require "test_helper"

class TodoTest < Minitest::Test
  def setup
    Hiiro::TodoItem.dataset.delete
    @harness = Hiiro::TestHarness.load_bin("bin/h-todo")
  end

  def test_add_change_status_list_and_remove_preserve_other_rows
    @harness.run_subcmd(:add, 'first', '-t', 'urgent')
    first = Hiiro::TodoItem.first
    second = Hiiro::TodoItem.create(text: 'external', task_name: 'feature', branch: 'branch')
    @harness.run_subcmd(:change, first.id.to_s, '--text', 'edited')
    @harness.run_subcmd(:done, first.id.to_s)
    assert_equal ['edited', 'urgent', 'done'], Hiiro::TodoItem[first.id].values.values_at(:text, :tags, :status)
    assert_equal ['external', 'feature', 'branch'], Hiiro::TodoItem[second.id].values.values_at(:text, :task_name, :branch)
    output, = capture_io { @harness.run_subcmd(:ls, '-a') }
    assert_equal "#{first.id} [x] edited  [urgent]\n#{second.id} [ ] external  (feature)\n", output
    @harness.run_subcmd(:rm, first.id.to_s)
    assert_equal [[second.id, 'external']], Hiiro::TodoItem.order(:id).all.map { |row| [row.id, row.text] }
  end

  def test_editall_updates_database_projection_preserving_context_and_external_rows
    item = Hiiro::TodoItem.create(text: 'original', task_name: 'feature', branch: 'branch', tags: 'old')
    @harness.define_singleton_method(:edit_files) do |path|
      rows = YAML.safe_load_file(path)
      rows.first['text'] = 'edited'
      Hiiro::TodoItem[item.id].update(tags: 'external')
      Hiiro::TodoItem.create(text: 'external-row')
      File.write(path, rows.to_yaml)
      true
    end
    @harness.run_subcmd(:editall)
    assert_equal ['edited', 'feature', 'branch', 'external'], Hiiro::TodoItem[item.id].values.values_at(:text, :task_name, :branch, :tags)
    assert_equal ['edited', 'external-row'], Hiiro::TodoItem.order(:id).select_map(:text)
  end
end
