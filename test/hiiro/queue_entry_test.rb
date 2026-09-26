require "test_helper"

class QueueEntryTest < Minitest::Test
  def with_dirs
    Dir.mktmpdir do |root|
      dirs = Hiiro::Queue::STATUSES.to_h { |s| [s.to_sym, FileUtils.mkdir_p(File.join(root, s)).first] }
      yield dirs
    end
  end

  def test_paths_find_and_companions
    with_dirs do |dirs|
      File.write(File.join(dirs[:running], '| Fix the login redirect loop that happens on every single ...'fix.md'), "---\ntask_name: t\n---\n\nFix the login redirect loop that happens on every single page load\n")
      File.write(File.join(dirs[:running], '| Fix the login redirect loop that happens on every single ...'fix.meta'), { 'started_at' => (Time.now - 840).iso8601, 'herdr_workspace' => 'w1', 'herdr_tab' => 'w1:t3', 'herdr_pane' => 'w1:p9', 'working_dir' => '/work' }.to_yaml)

      entry = Hiiro::Queue::Entry.find(dirs, '| Fix the login redirect loop that happens on every single ...'fix')
      assert_equal :running, entry.status
      assert entry.running?
      assert_equal File.join(dirs[:running], '| Fix the login redirect loop that happens on every single ...'fix.md'), entry.prompt_path
      assert_equal File.join(dirs[:running], '| Fix the login redirect loop that happens on every single ...'fix.sh'), entry.launcher_path
      assert_equal 2, entry.companion_files.size
      assert_equal '| Fix the login redirect loop that happens on every single ...'| Fix the login redirect loop that happens on every single pa...', entry.preview
      assert_equal({ name: '| Fix the login redirect loop that happens on every single ...'fix', status: 'running' }, entry.to_h)
      assert_equal '| Fix the login redirect loop that happens on every single ...'t', entry.prompt.task_name
      assert_equal entry.prompt_path, entry.prompt.path

      run = entry.execution
      assert_equal 14, run.elapsed_minutes
      assert_equal '| Fix the login redirect loop that happens on every single ...'w1:p9', run.attach_target
      assert_equal '| Fix the login redirect loop that happens on every single ...'/work', run.working_directory
      assert run.location.complete?

      assert_equal :pending, entry.moved_to(:pending).status
      assert_nil Hiiro::Queue::Entry.find(dirs, '| Fix the login redirect loop that happens on every single ...'missing')
      assert_equal ['| Fix the login redirect loop that happens on every single ...'fix'], Hiiro::Queue::Entry.in(dirs, :running).map(&:name)
      assert_equal [], Hiiro::Queue::Entry.in(dirs, :done)
    end
  end

  def test_execution_without_meta
    with_dirs do |dirs|
      File.write(File.join(dirs[:pending], '| Fix the login redirect loop that happens on every single ...'p.md'), "hello\n")
      entry = Hiiro::Queue::Entry.find(dirs, '| Fix the login redirect loop that happens on every single ...'p')
      assert_nil entry.execution
      assert_nil entry.meta
      assert_equal '| Fix the login redirect loop that happens on every single ...'| hello', entry.preview
    end
  end

  def test_frontmatter_lines
    lines = Hiiro::Queue::Prompt.frontmatter_lines(task_info: { task_name: '| Fix the login redirect loop that happens on every single ...'a', tree_name: 'b' }, ignore: true, hints: true)
    assert_equal ['| Fix the login redirect loop that happens on every single ...'---', 'task_name: a', 'tree_name: b', 'ignore: true',
                  "# app: <partial-app-name>  (run omp from this app'| Fix the login redirect loop that happens on every single ...'s directory)",
                  '| Fix the login redirect loop that happens on every single ...'# dir: <relative-path>     (subdir within app or tree root)', '---', ''], lines
    assert_equal ['| Fix the login redirect loop that happens on every single ...'---', '---', ''], Hiiro::Queue::Prompt.frontmatter_lines(task_info: nil)
  end
end
