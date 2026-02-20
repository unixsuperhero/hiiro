require "test_helper"

class TodoTest < Minitest::Test
  def setup
    @mock_tm = MockTodoManager.new
    mock = @mock_tm

    @harness = Hiiro::TestHarness.load_bin("bin/h-todo") do
      # The bin file creates tm at top level, we need to stub it
      # Since tm is a local variable in the block, we redefine the methods
      # that use it
    end

    # Replace the tm reference - this is tricky because tm is captured in closures
    # For now, just test subcommand registration
  end

  def test_registers_expected_subcommands
    expected = %i[ls list add rm remove change start done skip reset search path editall help]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_editall_opens_editor
    # editall calls system with editor
    @harness.run_subcmd(:editall)

    assert_equal 1, @harness.system_calls.size
  end

  class MockTodoManager
    attr_accessor :items

    def initialize
      @items = []
    end

    def todo_file
      "/tmp/test_todo.yml"
    end

    def active
      @items.select { |i| i[:status] != 'done' && i[:status] != 'skip' }
    end

    def all
      @items
    end

    def list(items)
      items.map { |i| "#{i[:text]}" }.join("\n")
    end

    def format_item(item)
      item[:text]
    end

    def add(text, tags: nil)
      item = { text: text, tags: tags, status: 'not_started' }
      @items << item
      item
    end
  end
end
