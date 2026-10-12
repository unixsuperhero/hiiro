require 'test_helper'
require 'open3'

class QueueHerdrTest < Minitest::Test
  def setup
    Hiiro::TaskResource.dataset.delete
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
    @dir = File.realpath(Dir.mktmpdir('hiiro-queue-'))
    @dirs = Hiiro::Queue::STATUSES.to_h { |status| [status.to_sym, FileUtils.mkdir_p(File.join(@dir, status)).first] }
    @root = File.join(@dir, 'code')
    FileUtils.mkdir_p(File.join(@root, 'api', 'src'))
    Hiiro::TaskRecord.create(name: 'review', primary_directory: @root, session: 'hq')
    Hiiro::TaskRecord.create(name: 'review-other', primary_directory: File.join(@dir, 'other'))
    Hiiro::AppRecord.create(name: 'api', path: 'api')
    Hiiro::AppRecord.create(name: 'api-other', path: 'missing')
    @executor = Hiiro::Effects::NullExecutor.new
    @executor.stub('workspace list', JSON.generate('result' => { 'workspaces' => [
      { 'workspace_id' => 'w1', 'label' => 'hq', 'worktree' => { 'checkout_path' => @root } },
      { 'workspace_id' => 'w2', 'label' => 'hq-other', 'worktree' => { 'checkout_path' => @dir } },
    ] }))
    @executor.stub('tab create', JSON.generate('result' => {
      'tab' => { 'tab_id' => 'w1:t2', 'workspace_id' => 'w1' },
      'root_pane' => { 'pane_id' => 'w1:p2', 'workspace_id' => 'w1', 'tab_id' => 'w1:t2' },
    }))
    herdr = Hiiro::Herdr.new(executor: @executor)
    @queue = Hiiro::Queue.new(Struct.new(:herdr_client).new(herdr),
      context: Hiiro::TaskLocation.for(nil, root: @dir, invocation_directory: @dir, terminal: Hiiro::Herdr::Location.new))
    @queue.instance_variable_set(:@queue_dirs, @dirs)
  end

  def teardown
    FileUtils.remove_entry(@dir)
    Hiiro::TaskResource.dataset.delete
    Hiiro::TaskRecord.dataset.delete
    Hiiro::AppRecord.dataset.delete
  end

  def prompt(fields, name: 'review')
    path = File.join(@dirs[:pending], "#{name}.md")
    File.write(path, "---\n#{fields.to_yaml.sub(/\A---\n/, '')}---\nReview the change\n")
    path
  end

  def test_launch_and_pane_dir_agree_for_exact_task_app_and_relative_directory
    path = prompt({ 'task_name' => 'review', 'app' => 'api', 'dir' => 'src', 'ignore' => true })
    expected = File.join(@root, 'api', 'src')
    assert_equal expected, @queue.resolve_pane_dir(path, @dir)
    @queue.launch_task('review')
    meta = YAML.safe_load_file(File.join(@dirs[:running], 'review.meta'))
    assert_equal expected, meta['working_dir']
    assert_equal 'w1:p2', meta['herdr_pane']
    assert_equal "Review the change\n", File.read(File.join(@dirs[:running], 'review.prompt'))
    refute File.exist?(path)
  end

  def test_invalid_frontmatter_leaves_pending_and_creates_no_launch_artifacts
    [
      { 'task_name' => 'missing' },
      { 'task_name' => 'rev' },
      { 'task_name' => 'review', 'app' => 'ap' },
      { 'task_name' => 'review', 'app' => 'absent' },
      { 'task_name' => 'review', 'dir' => 'absent' },
      { 'task_name' => 'review', 'dir' => '' },
      { 'task_name' => 'review', 'tree_name' => File.join(@dir, 'absent') },
      { 'task_name' => 'review', 'session_name' => 'absent' },
      { 'task_name' => 'review', 'dir' => '..' },
    ].each do |fields|
      path = prompt(fields)
      original = File.binread(path)
      assert_raises(Hiiro::Error, fields.inspect) { @queue.launch_task('review') }
      assert_equal original, File.binread(path)
      assert_equal [], Dir.children(@dirs[:running])
    end
  end

  def test_workspace_exact_and_unique_prefix_and_explicit_tree_use_same_resolver
    path = prompt({ 'session_name' => 'hq', 'app' => 'api' })
    assert_equal File.join(@root, 'api'), @queue.resolve_pane_dir(path)
    path = prompt({ 'session_name' => 'hq-o' })
    assert_equal @dir, @queue.resolve_pane_dir(path)
    path = prompt({ 'task_name' => 'review', 'tree_name' => @dir, 'dir' => 'code' })
    assert_equal @root, @queue.resolve_pane_dir(path)
    path = prompt({ 'session_name' => 'h' })
    assert_raises(Hiiro::Error) { @queue.resolve_pane_dir(path) }
  end

  def test_symlink_escape_is_rejected
    File.symlink(@dir, File.join(@root, 'outside'))
    path = prompt({ 'task_name' => 'review', 'dir' => 'outside' })
    error = assert_raises(Hiiro::Error) { @queue.resolve_pane_dir(path) }
    assert_match(/escapes/, error.message)
  end

  def test_cancelled_picker_never_uses_default_task
    @queue.stub(:select_task_or_session, nil) do
      error = assert_raises(Hiiro::Error) do
        @queue.resolve_task_info(OpenStruct.new(find: true), nil, { task_name: 'review' })
      end
      assert_match(/cancelled/, error.message)
    end
  end

  def test_injected_task_directory_survives_prefilled_frontmatter
    task = Hiiro::TaskRecord.find_by_name('review')
    selected = Hiiro::TaskLocation.for(task, invocation_directory: @dir, override: File.join(@root, 'api'))
    @queue.instance_variable_set(:@context, selected)
    path = prompt({ 'task_name' => 'review' })
    assert_equal File.join(@root, 'api'), @queue.resolve_pane_dir(path, @dir)
  end

  def test_invalid_add_writes_no_pending_prompt
    error = assert_raises(Hiiro::Error) do
      @queue.add_with_frontmatter("---\ntask_name: review\napp: missing\n---\nUnsafe")
    end
    assert_match(/App not found/, error.message)
    assert_equal [], Dir.children(@dirs[:pending])
  end

  def test_unique_task_prefix_resolves_the_canonical_directory
    path = prompt({ 'task_name' => 'review-o', 'tree_name' => @root, 'app' => 'api' })
    assert_equal File.join(@root, 'api'), @queue.resolve_pane_dir(path, @dir)
  end

  def test_launcher_stops_when_directory_disappears
    prompt({ 'task_name' => 'review', 'ignore' => true })
    @queue.launch_task('review')
    FileUtils.remove_entry(@root)
    executable = File.join(@dir, 'omp')
    marker = File.join(@dir, 'provider-started')
    File.write(executable, "#!/bin/sh\n/usr/bin/touch #{Shellwords.shellescape(marker)}\n")
    FileUtils.chmod(0755, executable)
    _out, err, status = Open3.capture3({ 'PATH' => @dir }, '/bin/bash', File.join(@dirs[:running], 'review.sh'))
    refute status.success?
    assert_match(/No such file or directory/, err)
    refute File.exist?(marker)
    assert File.exist?(File.join(@dirs[:running], 'review.md'))
  end
end
