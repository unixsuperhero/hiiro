require 'test_helper'
require_relative '../support/cli_sandbox'

# h pm queues /project-manager prompts in the pending queue in process,
# named pm-SUBCMD[-ARGS]; with no subcommand it chooses one in the picker.
class PmTest < Minitest::Test
  include CliSandbox

  def setup
    setup_sandbox
    ruby_in_sandbox('Hiiro::DB.setup!')
    @pending = File.join(@home, '.local/share/hiiro/queue/pending')
  end

  def teardown = teardown_sandbox

  def test_subcommands_queue_named_prompts
    assert_equal ["Created: #{@pending}/pm-status-proj.md\n", '', 0], run_bin('h-pm', 'status', 'proj')
    assert_equal ["Created: #{@pending}/pm-status-proj-2.md\n", '', 0], run_bin('h-pm', 'status', 'proj')
    assert_equal ["Created: #{@pending}/pm-ref-proj-https-x-test-a-b.md\n", '', 0], run_bin('h-pm', 'ref', 'proj', 'https://x.test/a b')

    assert_equal({ 'pm-ref-proj-https-x-test-a-b.md' => "/project-manager ref proj https://x.test/a b\n",
                   'pm-status-proj-2.md' => "/project-manager status proj\n",
                   'pm-status-proj.md' => "/project-manager status proj\n" },
                 Dir.children(@pending).sort.to_h { |name| [name, File.read(File.join(@pending, name))] })
  end

  def test_default_chooses_a_subcommand_in_the_picker
    out, status, frame = pick('h-pm', [], "jj\r")
    assert_equal ['pm-commands  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded',
                  '   discover      Auto-discover projects/tasks from PRs, worktrees, olive runs',
                  "   resume        Show 'where was I?' session briefing for a project",
                  '>  status        Show project status overview'], frame[0..4]
    assert_equal ["Created: #{@pending}/pm-status.md\n", 0], [out, status]
    assert_equal "/project-manager status\n", File.read(File.join(@pending, 'pm-status.md'))

    assert_equal ['', 0], pick('h-pm', [], 'q').first(2)
    assert_equal ['pm-status.md'], Dir.children(@pending)
  end

  def test_help_text
    out, _, status = run_bin('h-pm', 'help')
    assert_equal 0, status
    assert_equal ['h-pm — Queue /project-manager skill prompts via h queue add', '', 'USAGE:',
                  '  h pm                               Interactive: pick command'], out.lines(chomp: true).first(4)
    assert_equal 'Each command builds a /project-manager prompt and queues it via h queue add.', out.lines(chomp: true).last
  end
end
