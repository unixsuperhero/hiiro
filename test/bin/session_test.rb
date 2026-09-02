require 'test_helper'

class SessionTest < Minitest::Test
  def setup
    @mock_herdr = MockHerdr.new
    mock = @mock_herdr
    @harness = Hiiro::TestHarness.load_bin('bin/h-session') do
      define_singleton_method(:herdr_client) { mock }
    end
  end

  def test_registers_supported_herdr_workspace_subcommands
    expected = %i[ls list new kill attach rename switch has info open sh select copy orphans okill]
    expected.each { |subcmd| assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd}" }
  end

  def test_ls_with_args_calls_herdr_workspace_list
    @harness.run_subcmd(:ls, '--json')
    assert_equal [['herdr', 'workspace', 'list', '--json']], @harness.system_calls
  end

  def test_new_creates_focused_workspace
    @harness.run_subcmd(:new, 'feature', '/code/feature')
    assert_equal [{ name: 'feature', start_directory: '/code/feature', focus: true }], @mock_herdr.new_workspace_calls
  end

  def test_kill_resolves_and_closes_workspace
    @mock_herdr.workspaces_list = [MockWorkspace.new('w2', 'feature')]
    @harness.run_subcmd(:kill, 'feature')
    assert_equal ['w2'], @mock_herdr.closed_workspaces
  end

  def test_attach_focuses_workspace
    @mock_herdr.workspaces_list = [MockWorkspace.new('w2', 'feature')]
    @harness.run_subcmd(:attach, 'feature')
    assert_equal ['w2'], @mock_herdr.focused_workspaces
  end

  class MockHerdr
    attr_accessor :workspaces_list
    attr_reader :new_workspace_calls, :closed_workspaces, :focused_workspaces

    def initialize
      @workspaces_list = []
      @new_workspace_calls = []
      @closed_workspaces = []
      @focused_workspaces = []
    end

    def workspaces = @workspaces_list
    def panes(**) = []
    def tabs(**) = []
    def new_workspace(name, **options) = @new_workspace_calls << options.merge(name: name)
    def close_workspace(target) = @closed_workspaces << target
    def focus_workspace(target) = @focused_workspaces << target
    def rename_workspace(*) = nil
    def open_workspace(*) = nil
    def workspace_exists?(*) = false
    def current_workspace = @workspaces_list.first
    def find_workspace(target) = @workspaces_list.find { |workspace| [workspace.id, workspace.name].include?(target) }
  end

  MockWorkspace = Data.define(:id, :name) do
    def to_s = name
  end
end
