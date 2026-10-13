require 'test_helper'

class JobScreenTest < Minitest::Test
  def setup
    [Hiiro::JobClaim, Hiiro::JobOutcome].each { |model| model.dataset.delete }
  end

  def record(n, definition: 'nightly', outcome: 'completed')
    Hiiro::JobOutcome.record!(run_id: "run-#{n}", definition: definition, occurrence: "o#{n}", started_at: format('2026-10-13T12:%02d:00Z', n),
      finished_at: format('2026-10-13T12:%02d:30Z', n), outcome: outcome, exit_code: outcome == 'completed' ? 0 : 3, detail: "cycle #{n}")
  end

  def keys(screen, *keys) = keys.each { |key| screen.handle_key(key) }

  def test_background_refresh_keeps_query_selection_and_scroll
    (1..8).each { |n| record(n, definition: n.even? ? 'loop-prs' : 'nightly', outcome: n == 4 ? 'failed' : 'completed') }
    screen = Hiiro::JobScreen.new(interval: 1)
    keys(screen, '/', *'loop'.chars, :enter, 'j', 'j')
    before = screen.frame(rows: 4, cols: 140)
    assert_equal [
      'job outcomes  8 rows  r reload  / search  q quit',
      '  2026-10-13 12:06:30  loop-prs          completed exit 0  cycle 6   │run       run-4',
      '> 2026-10-13 12:04:30  loop-prs          failed exit 3     cycle 4   │schedule  loop-prs',
      '/loop  3/4',
    ], before

    record(9, definition: 'loop-prs')
    record(10, definition: 'loop-prs')
    record(11, definition: 'nightly')
    screen.refresh!
    after = screen.frame(rows: 4, cols: 140)
    assert_equal [
      'job outcomes  11 rows  r reload  / search  q quit',
      '  2026-10-13 12:06:30  loop-prs          completed exit 0  cycle 6   │run       run-4',
      '> 2026-10-13 12:04:30  loop-prs          failed exit 3     cycle 4   │schedule  loop-prs',
      '/loop  5/6',
    ], after
    assert_equal [3, 4], [screen.top, screen.cursor]
    assert_equal :list, screen.state.mode
    assert_equal 'loop', screen.state.query
  end

  def test_refresh_after_the_selected_row_disappears_clamps_inside_the_list
    (1..3).each { |n| record(n) }
    screen = Hiiro::JobScreen.new(interval: 1)
    keys(screen, 'j', 'j')
    Hiiro::JobOutcome.where(run_id: 'run-1').delete
    screen.refresh!
    assert_equal ['run-2', 2], [screen.send(:current_item).key, screen.cursor + 1]
  end

  def test_detail_shows_outcome_log_tail_and_artifacts
    Dir.mktmpdir do |dir|
      log = File.join(dir, 'run.log')
      File.write(log, (1..10).map { |n| "line #{n}" }.join("\n") + "\n")
      Hiiro::JobOutcome.record!(run_id: 'run-x', definition: 'nightly', occurrence: 'o', finished_at: '2026-10-13T12:00:00Z',
        outcome: 'failed', exit_code: 3, detail: 'exit 3', log_path: log, artifacts: [{ 'path' => '/tmp/a.txt', 'bytes' => 5 }], notification: 'failed')
      screen = Hiiro::JobScreen.new
      assert_equal ['run       run-x', 'schedule  nightly', 'occurs    o', 'outcome   failed exit 3', 'started   ',
                    'finished  2026-10-13T12:00:00Z', 'detail    exit 3', "log       #{log}", 'artifact  /tmp/a.txt (5 bytes)',
                    'notified  failed', '--- log tail ---', *(3..10).map { |n| "line #{n}" }],
        screen.detail_lines(screen.send(:current_item))
    end
  end
end
