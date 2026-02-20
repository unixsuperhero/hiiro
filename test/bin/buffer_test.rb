require "test_helper"

class BufferTest < Minitest::Test
  def setup
    @mock_tmux = MockTmux.new
    mock = @mock_tmux

    @harness = Hiiro::TestHarness.load_bin("bin/h-buffer") do
      define_singleton_method(:tmux_client) { mock }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[ls show copy save load set paste delete choose clear select]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_ls_with_args_calls_tmux_list_buffers
    @harness.run_subcmd(:ls, '-F', '#{buffer_name}')

    assert_equal [['tmux', 'list-buffers', '-F', '#{buffer_name}']], @harness.system_calls
  end

  def test_show_with_args_calls_system
    @mock_tmux.buffers_list = [MockBuffer.new("buffer0")]

    @harness.run_subcmd(:show, 'buffer0', '-F', '#{buffer_sample}')

    assert_equal [['tmux', 'show-buffer', '-b', 'buffer0', '-F', '#{buffer_sample}']], @harness.system_calls
  end

  def test_save_with_args_calls_system
    @harness.run_subcmd(:save, '/tmp/buf.txt', nil, '-a')

    assert_equal [['tmux', 'save-buffer', '/tmp/buf.txt', '-a']], @harness.system_calls
  end

  def test_load_with_args_calls_system
    @harness.run_subcmd(:load, '/tmp/buf.txt', '-b', 'mybuf')

    assert_equal [['tmux', 'load-buffer', '/tmp/buf.txt', '-b', 'mybuf']], @harness.system_calls
  end

  def test_set_calls_tmux_set_buffer
    @harness.run_subcmd(:set, '-b', 'mybuf', 'content')

    assert_equal [['tmux', 'set-buffer', '-b', 'mybuf', 'content']], @harness.system_calls
  end

  def test_paste_with_args_calls_system
    @harness.run_subcmd(:paste, 'mybuf', '-d')

    assert_equal [['tmux', 'paste-buffer', '-b', 'mybuf', '-d']], @harness.system_calls
  end

  def test_delete_with_args_calls_system
    @harness.run_subcmd(:delete, 'mybuf', '-a')

    assert_equal [['tmux', 'delete-buffer', '-b', 'mybuf', '-a']], @harness.system_calls
  end

  def test_choose_with_args_calls_system
    @harness.run_subcmd(:choose, '-F', '#{buffer_name}')

    assert_equal [['tmux', 'choose-buffer', '-F', '#{buffer_name}']], @harness.system_calls
  end

  class MockTmux
    attr_accessor :buffers_list

    def initialize
      @buffers_list = []
    end

    def buffers
      MockBufferCollection.new(@buffers_list)
    end

    def show_buffer(name)
      "buffer content"
    end

    def save_buffer(path, name: nil)
    end

    def load_buffer(path)
    end

    def paste_buffer(name: nil)
    end

    def delete_buffer(name)
    end

    def choose_buffer
    end
  end

  class MockBufferCollection
    def initialize(buffers)
      @buffers = buffers
    end

    def each(&block)
      @buffers.each(&block)
    end

    def empty?
      @buffers.empty?
    end

    def size
      @buffers.size
    end

    def first
      @buffers.first
    end

    def matching(partial)
      MockBufferCollection.new(@buffers.select { |b| b.name.include?(partial) })
    end

    def name_map
      @buffers.each_with_object({}) { |b, h| h[b.name] = b.name }
    end

    def clear_all
      @buffers.clear
    end
  end

  class MockBuffer
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def to_s
      name
    end
  end
end
