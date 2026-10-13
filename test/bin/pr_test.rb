require 'test_helper'
require 'open3'
require 'rbconfig'

class PrAttachTest < Minitest::Test
  def test_attach_bare_tracked_number_writes_executable_launcher_without_native_launch
    root = File.expand_path('../..', __dir__)
    Dir.mktmpdir('hiiro-pr-attach-') do |dir|
      workdir = File.join(dir, 'workspace with spaces')
      FileUtils.mkdir_p(workdir)
      fixture = File.join(dir, 'adapters.rb')
      File.write(fixture, <<~RUBY)
        require 'hiiro'
        require #{File.join(root, 'plugins/pins.rb').inspect}
        Hiiro::DB.setup!
        Hiiro::PinnedPr.create(number: 7, repo: 'team/one', pinned: true,
          head_ref_name: 'feature/pr', task: 'fixture-task')

        class Environment
          def self.current = new
          def find_task(name)
            raise 'unexpected task' unless name == 'fixture-task'
            tree = Struct.new(:path).new(ENV.fetch('ATTACH_WORK_DIR'))
            Struct.new(:session_name, :tree).new('fixture-workspace', tree)
          end
        end

        class FixtureHerdr
          def find_workspace(name)
            raise 'unexpected workspace' unless name == 'fixture-workspace'
            'controlled-workspace'
          end

          def new_tab(**options)
            raise 'unexpected workspace selection' unless options.fetch(:workspace) == 'controlled-workspace'
            path = options.fetch(:command)
            puts JSON.dump({ executable: File.executable?(path), script: File.read(path) })
          ensure
            File.unlink(path) if path && File.file?(path)
          end
        end

        class Hiiro
          def herdr_client = FixtureHerdr.new
        end

        module Kernel
          def system(*) = raise('native process launch forbidden')
          def spawn(*) = raise('native process launch forbidden')
          def `(command) = raise('native process launch forbidden')
        end
        def Process.spawn(*) = raise('native process launch forbidden')
        def IO.popen(*) = raise('native process launch forbidden')
      RUBY
      environment = {
        'HOME' => dir,
        'HIIRO_TEST_DB' => "sqlite://#{File.join(dir, 'records.db')}",
        'ATTACH_WORK_DIR' => workdir,
      }
      stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby,
        '-I', File.join(root, 'lib'), '-r', fixture, File.join(root, 'bin/h-pr'), 'attach', '7')
      assert status.success?, stderr
      result = JSON.parse(stdout)
      assert_equal true, result.fetch('executable')
      assert_includes result.fetch('script').lines.map(&:chomp), "cd #{Shellwords.shellescape(workdir)}"
      assert_includes result.fetch('script').lines.map(&:chomp), 'git checkout feature/pr'
    end
  end
end

require_relative '../support/fake_gh'

# Actual h-pr subprocesses against a controlled gh (fixture PATH plus system
# directories only) and a file-backed database.
class PrSnapshotCliTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  A = 'a' * 40
  B = 'b' * 40

  def setup
    @dir = Dir.mktmpdir('hiiro-pr-cli-')
    @bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p([@bin, File.join(@dir, 'home')])
    @state = File.join(@dir, 'state.json')
    @log = File.join(@dir, 'gh.log')
    @db = File.join(@dir, 'hiiro.db')
    FakeGh.install(@bin, @state, @log)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def env
    { 'HOME' => File.join(@dir, 'home'), 'PATH' => "#{@bin}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'HIIRO_TEST_DB' => "sqlite://#{@db}" }.merge(ENV.slice('BUNDLE_PATH'))
  end

  def hpr_command = [RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/h-pr')]

  def pr(*args)
    out, status = Open3.capture2e(env, *hpr_command, *args, unsetenv_others: true)
    [out.gsub(/\e\[[0-9;]*m/, ''), status.exitstatus]
  end

  def gh_state(one: {}, hooks: nil)
    prs = { 'team/one#42' => { 'title' => 'one', 'state' => 'OPEN', 'head' => A, 'checks' => 250, 'reviews' => 130 }.merge(one),
            'team/two#42' => { 'title' => 'two', 'state' => 'OPEN', 'head' => B, 'checks' => [
              { '__typename' => 'CheckRun', 'name' => 'rspec', 'status' => 'COMPLETED', 'conclusion' => 'SUCCESS' },
              { '__typename' => 'CheckRun', 'name' => 'lint', 'status' => 'COMPLETED', 'conclusion' => 'FAILURE', 'detailsUrl' => 'https://ci.example.test/lint' },
            ], 'reviews' => 2 } }
    File.write(@state, JSON.generate({ 'repo' => 'team/one', 'prs' => prs, 'hooks' => hooks }.compact))
  end

  def rows(sql) = Sequel.sqlite(@db) { |db| db.fetch(sql).all }

  def test_same_number_in_two_repositories_stays_distinct_through_the_cli
    gh_state
    assert_equal ["Now tracking team/one#42: one", 0], [pr('track', 'https://github.com/team/one/pull/42').then { |o, c| [o.lines.first.chomp, c] }].flatten
    assert_equal 'Now tracking team/two#42: two', pr('track', 'team/two#42').first.lines.first.chomp
    assert_equal ["Already tracking team/one#42\n", 0], pr('track', '42')
    assert_equal ["ERROR: Ambiguous PR #42 (team/one#42, team/two#42); use owner/name#42 or its URL\n", 1], pr('rm', '42')

    out, code = pr('update', '-u')
    assert_equal 0, code
    assert_includes out, "1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 one\n"
    assert_includes out, "2. team/two#42 [o 　❌   1/  2]   2a/-cr branch-42 two\n"
    assert_equal [['team/one', 42, A, true, true, 'fresh', 250, 130], ['team/two', 42, B, true, true, 'fresh', 2, 2]],
                 rows("select repo, number, head_sha, checks_complete, reviews_complete, refresh_outcome, json_array_length(check_runs_json) c, json_array_length(review_nodes_json) r from prs order by id").map(&:values)
    assert_equal [[1, 250], [2, 2]], rows('select pr_id, count(*) n from check_runs group by pr_id order by pr_id').map(&:values)

    assert_equal ["Tagged team/two#42 with: two\n  Tags now: two\n", 0], pr('tag', 'team/two#42', 'two')
    out, = pr('ls', '-C', '-t', 'two')
    assert_equal ['2. team/two#42 [o 　❌ 1/2] 2a/-cr branch-42 two  two', '   ✅  rspec', '   ❌  lint', '      https://ci.example.test/lint', '---'], out.lines.map(&:chomp).first(5)

    assert_equal ["team/one#42 now depends on: team/two#42, team/one#7\n", 0], pr('dep', 'add', 'team/one#42', 'team/two#42', '7')
    assert_equal ["team/one#42: one\n  └─ team/two#42: two\n  └─ team/one#7 (not tracked)\n", 0], pr('dep', 'ls')
    assert_equal ["Removed dep(s) team/two#42 from team/one#42\n  Remaining: team/one#7\n", 0], pr('dep', 'rm', 'team/one#42', 'https://github.com/team/two/pull/42')

    assert_equal ["Removed team/one#42 from tracking\n", 0], pr('rm', 'team/one#42')
    assert_equal [[2, 'team/two', '["two"]']], rows('select id, repo, tags_json from prs').map(&:values)
    assert_equal [[2, 2]], rows('select pr_id, count(*) n from check_runs group by pr_id').map(&:values)
  end

  def test_partial_pages_and_head_changes_never_produce_passing_eligibility
    gh_state
    pr('track', 'team/one#42')
    gh_state(one: { 'fail' => { 'checks' => { '3' => 'exit' } } })
    out, = pr('update', '-u')
    assert_includes out, "  incomplete team/one#42: checks: page 3 failed: gh exited 1: HTTP 502: Bad Gateway (https://api.github.com/graphql)\n"
    assert_includes out, "1. team/one#42 [o 　❓ 200/200] 130a/-cr branch-42 incomplete one\n"
    assert_equal ["No PRs match.\n", 0], pr('green')

    gh_state
    pr('update', '-u')
    assert_equal ["42\n", 0], pr('green', '-n')
    observed = rows('select head_sha, fetched_at, check_runs_json, review_nodes_json from prs').first
    gh_state(one: { 'head_at' => { 'checks' => { '2' => B } } })
    out, = pr('update', '-u')
    assert_includes out, "  refresh failed team/one#42: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)\n"
    assert_includes out, "1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 stale one\n"
    assert_equal observed, rows('select head_sha, fetched_at, check_runs_json, review_nodes_json from prs').first
    assert_equal ["No PRs match.\n", 0], pr('green')
    out, code = pr('status', 'team/one#42')
    assert_equal ["team/one#42\none\nopen\n250 success\nsnapshot stale: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)\nhttps://github.com/team/one/pull/42\n", 1], [out, code]
  end

  def test_local_changes_made_during_a_refresh_survive_its_write
    gh_state
    pr('track', 'team/one#42')
    pr('tag', 'team/one#42', 'before')
    other = (['env'] + env.map { |k, v| "#{k}=#{v}" } + hpr_command).join(' ')
    gh_state(one: { 'title' => 'renamed', 'head' => B },
             hooks: { 'team/one#42:checks:2' => ['/bin/sh', '-c', "#{other} tag team/one#42 during && #{other} untag team/one#42 before"] })
    out, code = pr('update', '-u')
    assert_equal 0, code
    assert_includes out, "1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 renamed  during\n"
    assert_equal [['renamed', B, '["during"]', 'fresh']], rows('select title, head_sha, tags_json, refresh_outcome from prs').map(&:values)
  end
end
