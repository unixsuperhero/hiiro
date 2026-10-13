require 'test_helper'
require 'open3'

class QueueHerdrTest < Minitest::Test
  include OwnedRunHelpers

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
    @executor = FakeHerdrTerminal.new
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
    @store = run_store(@dir)
    @queue.launcher = Hiiro::OwnedRun::Launcher.new(store: @store, herdr: herdr)
    @bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p(@bin)
    @path = ENV['PATH']
    ENV['PATH'] = [@bin, '/usr/bin', '/bin'].join(':')
  end

  # A stand-in agent: records its cwd and arguments, copies the prompt it was
  # handed, and exits with the given status.
  def fake_omp(status)
    File.write(File.join(@bin, 'omp'), <<~SH)
      #!/bin/sh
      pwd > #{File.join(@dir, 'omp-cwd').shellescape}
      echo "$@" > #{File.join(@dir, 'omp-args').shellescape}
      for arg in "$@"; do case "$arg" in @*) cat "${arg#@}" > #{File.join(@dir, 'omp-prompt').shellescape};; esac; done
      exit #{status}
    SH
    FileUtils.chmod(0755, File.join(@bin, 'omp'))
  end

  def run_id_in(status, name = 'review')
    YAML.safe_load_file(File.join(@dirs[status], "#{name}.meta"))['run_id']
  end

  def teardown
    ENV['PATH'] = @path
    @executor.wait_all
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
    fake_omp(0)
    path = prompt({ 'task_name' => 'review', 'app' => 'api', 'dir' => 'src', 'ignore' => true })
    expected = File.join(@root, 'api', 'src')
    assert_equal expected, @queue.resolve_pane_dir(path, @dir)
    run = @queue.launch_task('review')
    refute File.exist?(path)
    assert_equal 'completed exit 0', wait_for_run(@store, run.id).summary
    meta = YAML.safe_load_file(File.join(@dirs[:done], 'review.meta'))
    assert_equal expected, meta['working_dir']
    assert_equal 'w1:p2', meta['herdr_pane']
    assert_equal run.id, meta['run_id']
    assert_equal expected, File.read(File.join(@dir, 'omp-cwd')).strip
    assert_equal "-p @#{File.join(@dirs[:running], 'review.prompt')}", File.read(File.join(@dir, 'omp-args')).strip
    assert_equal "Review the change\n", File.read(File.join(@dir, 'omp-prompt'))
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:done]).sort
    assert_equal [], Dir.children(@dirs[:running])
  end

  def test_nonzero_agent_exit_fails_the_entry_and_leaves_the_task_open
    fake_omp(7)
    Hiiro::TaskRecord.find_by_name('review').update(status: 'active')
    prompt({ 'task_name' => 'review' })
    run = @queue.launch_task('review')
    assert_equal 'failed exit 7', wait_for_run(@store, run.id).summary
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:failed]).sort
    assert_equal [], Dir.children(@dirs[:running])
    assert_equal run.id, run_id_in(:failed)
    assert_equal 'active', Hiiro::TaskRecord.find_by_name('review').status
  end

  def test_agent_that_cannot_start_fails_the_entry_and_retry_recovers_it
    prompt({ 'task_name' => 'review' })
    error = assert_raises(Hiiro::OwnedRun::LaunchError) { @queue.launch_task('review') }
    assert_equal 'failed', error.run.state
    assert_nil error.run.process
    assert_match(/\Aomp @.*No such file or directory/, error.run.error)
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:failed]).sort

    FileUtils.mv(File.join(@dirs[:failed], 'review.md'), File.join(@dirs[:pending], 'review.md'))
    fake_omp(0)
    retried = @queue.launch_task('review')
    assert_equal 'completed exit 0', wait_for_run(@store, retried.id).summary
    assert File.exist?(File.join(@dirs[:done], 'review.md'))
  end

  def test_tab_allocation_failure_leaves_a_failed_entry_not_a_running_one
    @executor.stub('tab create', '{}')
    prompt({ 'task_name' => 'review' })
    error = assert_raises(Hiiro::OwnedRun::LaunchError) { @queue.launch_task('review') }
    assert_equal 'failed: Herdr did not create a tab (no tab)', error.run.summary
    assert_equal [], Dir.children(@dirs[:running])
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:failed]).sort
    assert_equal error.run.id, run_id_in(:failed)
  end

  def test_undelivered_command_closes_the_tab_and_fails_the_entry
    @executor.deliver = false
    prompt({ 'task_name' => 'review' })
    error = assert_raises(Hiiro::OwnedRun::LaunchError) { @queue.launch_task('review') }
    assert_equal 'failed: Herdr did not run the command in pane w1:p2', error.run.summary
    assert @executor.calls_to(:run).any? { |call| call[:args] == %w[herdr tab close w1:t2] }
    assert_equal [], Dir.children(@dirs[:running])
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:failed]).sort
  end

  def test_kill_signals_the_recorded_agent_and_waits_for_its_outcome
    File.write(File.join(@bin, 'omp'), "#!/bin/sh\nexec sleep 30\n")
    FileUtils.chmod(0755, File.join(@bin, 'omp'))
    prompt({ 'task_name' => 'review' })
    run = @queue.launch_task('review')
    assert run.process.alive?
    killed = @queue.kill('review')
    refute run.process.alive?
    assert_equal 'failed signal TERM', killed.summary
    assert_equal %w[review.md review.meta], Dir.children(@dirs[:failed]).sort
    assert_equal [], Dir.children(@dirs[:running])
  end

  def test_competing_launchers_have_exactly_one_claimant
    root = File.join(@dir, 'claims')
    FileUtils.mkdir_p(File.join(root, 'pending'))
    File.write(File.join(root, 'pending', 'job.md'), 'job')
    lib = File.expand_path('../../lib', __dir__)
    script = "require 'hiiro/queue_claim'; $stdin.read; print(Hiiro::QueueClaim.claim(ARGV[0], 'job') ? 'won' : 'lost')"
    gate_reader, gate_writer = IO.pipe
    results = 6.times.map do
      reader, writer = IO.pipe
      pid = Process.spawn(RbConfig.ruby, '-I', lib, '-e', script, root, in: gate_reader, out: writer)
      writer.close
      [pid, reader]
    end
    gate_reader.close
    gate_writer.close
    outcomes = results.map { |pid, reader| Process.wait(pid); reader.read }
    assert_equal ['won'], outcomes.select { |outcome| outcome == 'won' }
    assert_equal 5, outcomes.count('lost')
    assert_equal ['job.md'], Dir.children(File.join(root, 'running'))
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
end
