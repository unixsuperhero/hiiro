require 'test_helper'

class CaptureModelTest < Minitest::Test
  def test_migrate_adds_run_evidence_columns_once_and_keeps_existing_rows
    db = Sequel.sqlite
    db.create_table(:captures) do
      primary_key :id
      String :name, null: false
      String :path, null: false
      String :command
      Integer :exit_status
    end
    db[:captures].insert(id: 7, name: 'old', path: '/tmp/old.log', command: 'false', exit_status: 1)

    2.times { Hiiro::Capture.migrate!(db) }

    assert_equal %i[id name path command exit_status source run_id cwd started_at finished_at outcome exit_signal task_name context_json],
                 db.schema(:captures).map(&:first)
    assert_equal({ id: 7, name: 'old', path: '/tmp/old.log', command: 'false', exit_status: 1, source: nil, run_id: nil, cwd: nil,
                   started_at: nil, finished_at: nil, outcome: nil, exit_signal: nil, task_name: nil, context_json: nil }, db[:captures].first)
  ensure
    db&.disconnect
  end
end
