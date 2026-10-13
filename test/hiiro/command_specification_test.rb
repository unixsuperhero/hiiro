require "test_helper"

class CommandSpecificationTest < Minitest::Test
  def test_spec_normalizes_env_and_previews
    spec = Hiiro::CommandSpecification.new('echo', 'hi there', env: { FOO: 1 })
    assert_equal({ 'FOO' => '1' }, spec.env)
    assert_equal ['echo', 'hi there'], spec.argv
    assert_equal "echo hi\\ there", spec.preview
    assert_equal [{ 'FOO' => '1' }, 'echo', 'hi there'], spec.open3_args
    assert_equal [{}, 'ls', { chdir: '/tmp' }], Hiiro::CommandSpecification.new('ls', cwd: '/tmp').open3_args
  end

  def test_result_retains_spec
    result = Hiiro::Shell.run('sh', '-c', 'echo $GREETING', GREETING: 'yo')
    assert_equal "yo\n", result.stdout
    assert_equal ['sh', '-c', 'echo $GREETING'], result.spec.argv
    assert_equal({ 'GREETING' => 'yo' }, result.spec.env)
    assert_equal "sh -c echo\\ \\$GREETING", result.command

    combined = Hiiro::Shell.run_combined('sh', '-c', 'echo out; echo err 1>&2')
    assert_equal "out\nerr\n", combined.stdout
    assert combined.spec

    three = Hiiro::Shell.run3('sh', '-c', 'echo err 1>&2')
    assert_equal "err\n", three.stderr
    assert_equal 'sh', three.spec.argv.first

    streamed = Hiiro::Shell.stream('echo', 'x', tee: nil)
    assert_equal 'echo x', streamed.command
  end

  def test_shell_text_stays_distinct_from_argv_and_round_trips
    shell = Hiiro::CommandSpecification.shell('echo "$HOME" | wc -c', cwd: '/tmp', env: { A: 1 })
    assert_equal :shell, shell.kind
    assert_equal 'echo "$HOME" | wc -c', shell.preview
    assert_equal ['/bin/bash', '-c', 'echo "$HOME" | wc -c'], shell.argv
    assert_equal({ 'kind' => 'shell', 'env' => { 'A' => '1' }, 'cwd' => '/tmp', 'shell' => 'echo "$HOME" | wc -c' }, shell.to_h)
    assert_equal shell.argv, Hiiro::CommandSpecification.from_h(shell.to_h).argv

    argv = Hiiro::CommandSpecification.new('printf', '%s', 'a b')
    assert_equal :argv, argv.kind
    assert_equal({ 'kind' => 'argv', 'env' => {}, 'cwd' => nil, 'argv' => ['printf', '%s', 'a b'] }, argv.to_h)
    assert_equal [{}, 'printf', '%s', 'a b', { pgroup: true }], argv.spawn_args(pgroup: true)
  end

  def test_process_outcome_separates_signals_from_exit_codes
    _, seven = Process.wait2(Process.spawn('/bin/sh', '-c', 'exit 7'))
    outcome = Hiiro::ProcessOutcome.from_status(seven)
    assert_equal [7, nil, false, 7, 'exit 7'], [outcome.exit_code, outcome.signal, outcome.success?, outcome.shell_code, outcome.to_s]

    pid = Process.spawn('/bin/sh', '-c', 'kill -TERM $$')
    _, killed = Process.wait2(pid)
    outcome = Hiiro::ProcessOutcome.from_status(killed)
    assert_equal [nil, 'TERM', false, 143, 'signal TERM'], [outcome.exit_code, outcome.signal, outcome.success?, outcome.shell_code, outcome.to_s]
  end

  def test_stream_writes_each_chunk_once
    out = StringIO.new
    result = Hiiro::Shell.stream('printf', 'one\ntwo\n', tee: out)
    assert_equal "one\ntwo\n", out.string
    assert_equal "one\ntwo\n", result.stdout
  end
end
