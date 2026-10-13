require 'test_helper'
require 'stringio'

# In-process monitor cycles over stored snapshots: the fetcher answers from a
# block, notifications and queue additions are recorded (and can fail).
class PrMonitorTest < Minitest::Test
  A = 'a' * 40
  B = 'b' * 40
  PENDING = { '__typename' => 'CheckRun', 'name' => 'build', 'status' => 'IN_PROGRESS', 'conclusion' => nil }.freeze
  FAILED = { '__typename' => 'CheckRun', 'name' => 'lint', 'status' => 'COMPLETED', 'conclusion' => 'FAILURE',
             'detailsUrl' => 'https://ci.example.test/lint' }.freeze
  PASSED = { '__typename' => 'CheckRun', 'name' => 'lint', 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS' }.freeze
  APPROVAL = { 'author' => { 'login' => 'r' }, 'state' => 'APPROVED', 'submittedAt' => '2026-10-01T00:00:00Z' }.freeze

  class Queue
    attr_reader :jobs
    attr_accessor :fail

    def initialize = @jobs = []

    def add_with_frontmatter(content, name:)
      raise Hiiro::Error, 'Workspace not found: gone' if fail

      @jobs << [name, content]
      { name: name, path: "/queue/pending/#{name}.md" }
    end
  end

  def setup
    [Hiiro::PrMonitorCheckpoint, Hiiro::CheckRun, Hiiro::PinnedPr].each { |model| model.dataset.delete }
    @manager = Hiiro::PinnedPRManager.new
    @manager.instance_variable_set(:@code_freeze_active, nil)
    @notified = []
    @notify_ok = true
    @queue = Queue.new
    @readied = []
    @answers = {}
    fetcher = Object.new
    answers = @answers
    fetcher.define_singleton_method(:fetch) { |refs| refs.to_h { |ref| [ref, answers.fetch(ref.to_s).call(ref)] } }
    @manager.instance_variable_set(:@fetcher, fetcher)
  end

  def teardown
    [Hiiro::PrMonitorCheckpoint, Hiiro::CheckRun, Hiiro::PinnedPr].each { |model| model.dataset.delete }
  end

  def ref(text) = Hiiro::PullRequestReference.qualified(text)

  def track(text, **attrs)
    record, = @manager.track(ref(text))
    record.update(attrs) unless attrs.empty?
    record
  end

  def answer(text, head: A, checks: [PENDING], reviews: [], decision: nil, state: 'OPEN', draft: false,
             checks_complete: true, reviews_complete: true)
    @answers[text] = lambda do |reference|
      part = Hiiro::PrSnapshot::Part
      Hiiro::PrSnapshot.new(reference: reference, head_sha: head, fetched_at: Time.now.utc.iso8601(6),
        fields: { 'title' => text, 'state' => state, 'url' => reference.url, 'isDraft' => draft, 'reviewDecision' => decision },
        checks: part.new(nodes: checks, complete: checks_complete, error: checks_complete ? nil : 'checks: page 2 failed: HTTP 502'),
        reviews: part.new(nodes: reviews, complete: reviews_complete, error: nil))
    end
  end

  def failure(text, error)
    @answers[text] = ->(reference) { Hiiro::PrSnapshot::Failure.new(reference: reference, error: error) }
  end

  def cycle(**options)
    out = StringIO.new
    monitor = Hiiro::PrMonitor.new(manager: @manager, options: Hiiro::PrMonitor::Options.defaults.tap { |o| options.each { |k, v| o[k] = v } },
                                   notifier: ->(args) { @notified << args; @notify_ok },
                                   queue: -> { @queue }, ready: ->(r) { @readied << r.to_s; Hiiro::ProcessOutcome.new(exit_code: 0) },
                                   out: out)
    monitor.cycle
    out.string.lines.map(&:chomp)
  end

  def checkpoints = Hiiro::PrMonitorCheckpoint.order(:channel).all.map { |c| [c.channel, c.head_sha&.slice(0, 7), c.state, !c.delivered_at.nil?, c.detail] }

  def test_transitions_compare_checkpoints_with_one_observation
    observation = Hiiro::PrMonitor::Observation.new(reference: ref('team/one#42'), head_sha: B)
    checkpoint = ->(head, state) { Hiiro::PrMonitorCheckpoint.new(head_sha: head, state: state) }
    events = Hiiro::PrMonitor.transitions(
      { 'checks' => checkpoint.(A, 'failing'), 'review' => checkpoint.(A, 'approved'), 'fix' => checkpoint.(A, 'failing') },
      observation, { 'checks' => 'failing', 'review' => 'approved', 'dependencies' => 'waiting', 'fix' => 'unknown' })
    assert_equal [['checks', 'failing', 'failing', false], ['dependencies', nil, 'waiting', true]],
                 events.map { |e| [e.channel, e.from, e.to, e.baseline] }
  end

  def test_baseline_then_one_notification_per_transition_and_none_on_repeat
    track('team/one#42')
    answer('team/one#42')
    assert_equal ['team/one#42 checks baseline pending at aaaaaaa: baseline',
                  'team/one#42 review baseline review_required at aaaaaaa: baseline'], cycle
    assert_equal [], cycle
    answer('team/one#42', checks: [FAILED])
    assert_equal ['team/one#42 checks pending → failing at aaaaaaa: notified'], cycle
    assert_equal [], cycle
    assert_equal [['-t', 'PR checks failing', '-m', 'team/one#42: team/one#42 (aaaaaaa)', '-l', 'https://github.com/team/one/pull/42']], @notified
    assert_equal [['checks', 'aaaaaaa', 'failing', true, 'notified'], ['review', 'aaaaaaa', 'review_required', false, 'baseline']], checkpoints
  end

  def test_stale_partial_and_unknown_observations_never_pass_or_approve
    track('team/one#42')
    answer('team/one#42', checks: [PENDING])
    cycle
    answer('team/one#42', checks: [PASSED], checks_complete: false, reviews: [APPROVAL], decision: 'APPROVED', reviews_complete: false)
    assert_equal ['incomplete team/one#42: checks: page 2 failed: HTTP 502'], cycle
    failure('team/one#42', 'head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)')
    assert_equal ['refresh failed team/one#42: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)'], cycle
    assert_empty @notified
    assert_equal [['checks', 'aaaaaaa', 'pending', false, 'baseline'], ['review', 'aaaaaaa', 'review_required', false, 'baseline']], checkpoints

    answer('team/one#42', checks: [PASSED], reviews: [APPROVAL], decision: 'APPROVED')
    assert_equal ['team/one#42 checks pending → passing at aaaaaaa: notified',
                  'team/one#42 review review_required → approved at aaaaaaa: notified'], cycle
  end

  def test_new_head_is_a_new_event_and_a_review_decision_is_not
    track('team/one#42')
    answer('team/one#42', checks: [FAILED], reviews: [APPROVAL], decision: 'APPROVED')
    cycle
    answer('team/one#42', head: B, checks: [FAILED], reviews: [APPROVAL], decision: 'APPROVED')
    assert_equal ['team/one#42 checks failing → failing at bbbbbbb: notified'], cycle
  end

  def test_failed_notification_is_retried_and_delivered_once
    track('team/one#42')
    answer('team/one#42')
    cycle
    answer('team/one#42', checks: [FAILED])
    @notify_ok = false
    assert_equal ['team/one#42 checks pending → failing at aaaaaaa: failed; retried next cycle'], cycle
    @notify_ok = true
    assert_equal ['team/one#42 checks pending → failing at aaaaaaa: notified'], cycle
    assert_equal [], cycle
    assert_equal 2, @notified.length
  end

  def test_fix_queueing_is_opt_in_once_per_revision_and_retried_after_a_failed_addition
    track('team/one#42', task: 'work')
    answer('team/one#42')
    cycle
    answer('team/one#42', checks: [FAILED])
    cycle
    assert_empty @queue.jobs

    answer('team/one#42', head: B, checks: [PENDING])
    cycle(queue_fixes: true)
    answer('team/one#42', head: B, checks: [FAILED])
    @queue.fail = true
    assert_includes cycle(queue_fixes: true), 'team/one#42 fix pending → failing at bbbbbbb: failed; retried next cycle'
    assert_empty @queue.jobs
    @queue.fail = false
    assert_equal ['team/one#42 fix pending → failing at bbbbbbb: queued pr-fix-team-one-42-bbbbbbb'], cycle(queue_fixes: true)
    assert_equal [], cycle(queue_fixes: true)
    assert_equal 1, @queue.jobs.length
    name, content = @queue.jobs.first
    assert_equal 'pr-fix-team-one-42-bbbbbbb', name
    assert_equal <<~MD.chomp, content.sub(/fetched \S+,/, 'fetched T,')
      ---
      pr: team/one#42
      pr_url: https://github.com/team/one/pull/42
      head_sha: #{B}
      task_name: work
      ---
      /pr:fix https://github.com/team/one/pull/42

      PR: team/one#42 https://github.com/team/one/pull/42
      Head revision: #{B}
      Snapshot: fresh, fetched T, checks complete
      Failing checks:
      - lint FAILURE https://ci.example.test/lint
    MD
  end

  def test_dependency_completion_only_notifies
    track('team/one#42')
    track('team/two#5', depends_on: ['team/one#42'])
    answer('team/one#42', checks: [PASSED])
    answer('team/two#5', checks: [PASSED])
    cycle
    answer('team/one#42', checks: [PASSED], state: 'MERGED')
    assert_equal ['team/two#5 dependencies waiting → satisfied at aaaaaaa: notified'], cycle
    assert_equal [['-t', 'PR dependencies merged', '-m', 'team/two#5: team/two#5', '-l', 'https://github.com/team/two/pull/5']], @notified
    assert_empty @readied
  end

  def test_mark_ready_needs_opt_in_and_a_fresh_complete_passing_head
    track('team/one#42')
    answer('team/one#42', draft: true)
    cycle(mark_ready: true)
    answer('team/one#42', checks: [PASSED], checks_complete: false, draft: true)
    cycle(mark_ready: true)
    assert_empty @readied
    answer('team/one#42', checks: [PASSED], draft: true)
    assert_includes cycle(mark_ready: true), 'team/one#42 ready pending → passing at aaaaaaa: marked ready'
    assert_equal ['team/one#42'], @readied
  end
end
