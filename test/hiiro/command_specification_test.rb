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
end
