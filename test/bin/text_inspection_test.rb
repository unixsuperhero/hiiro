require 'test_helper'
require_relative '../support/cli_sandbox'

# `h ruby iface` and `h iface rb` are one TextInspection over named groups.
class TextInspectionTest < Minitest::Test
  include CliSandbox

  SOURCE = <<~RUBY
    module Shop
      class Cart
        attr_reader :items
        Line = Struct.new(:sku)
        def total = 0
        alias sum total
        private
        def secret; end
      end
    end
    describe Cart do
      let(:cart) { Cart.new }
      it 'adds' do
        Hiiro.run { add_subcmd(:x) {} }
      end
    end
  RUBY

  def setup
    setup_sandbox
    File.write(File.join(@home, 'cart.rb'), SOURCE)
    File.write(File.join(@home, 'plain.rb'), "x = 1\n")
  end

  def teardown = teardown_sandbox

  def report(path, *lines) = "\n  FILE: #{path}\n#{'=' * "  FILE: #{path}  ".length}\n#{lines.map { |l| "#{l}\n" }.join}\n"
  def src(*indexes) = indexes.map { |i| SOURCE.lines[i].chomp }

  def test_each_group_and_alias_prints_its_declarations
    {
      %w[class] => src(0, 1), %w[attributes] => src(2), %w[methods] => src(3, 4, 5, 7), %w[accessmodifiers] => src(6),
      %w[tests] => src(10, 12), %w[lets] => src(11), %w[hiiro] => src(13), %w[iface] => src(0, 1, 2, 3, 4, 5, 7),
      %w[all] => src(0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13), %w[att le] => src(2, 11), %w[me] => src(3, 4, 5, 7),
    }.each do |groups, lines|
      assert_equal [report('cart.rb', *lines), '', 0], run_bin('h-ruby', 'iface', *groups, 'cart.rb'), groups.join(' ')
    end
  end

  def test_iface_rb_uses_the_same_operation_and_default
    expected = report('cart.rb', *src(0, 1, 2, 3, 4, 5, 7))
    assert_equal [expected, '', 0], run_bin('h-iface', 'rb', 'cart.rb')
    assert_equal [expected, '', 0], run_bin('h-ruby', 'iface', 'cart.rb')
  end

  def test_a_file_without_declarations_exits_1_after_printing_every_file
    assert_equal [report('plain.rb') + report('cart.rb', *src(11)), '', 1], run_bin('h-iface', 'rb', 'lets', 'plain.rb', 'cart.rb')
  end

  def test_ambiguous_and_unknown_groups_and_missing_files_are_usage_errors
    assert_equal ['', "Ambiguous group: a (accessmodifiers, all, attributes)\n", 1], run_bin('h-ruby', 'iface', 'a', 'cart.rb')
    assert_match(/\AUnknown group or missing file: zz /, run_bin('h-ruby', 'iface', 'zz', 'cart.rb')[1])
    assert_equal ['', "Usage: h ruby iface [GROUP...] FILE...\n", 1], run_bin('h-ruby', 'iface', 'class')
  end

  def test_concurrent_inspections_keep_their_own_groups
    runs = %w[lets class tests hiiro].map do |group|
      Thread.new { [group, Open3.capture3(sandbox_env, *bin_argv('h-ruby', 'iface', group, 'cart.rb'), chdir: @home, unsetenv_others: true)] }
    end.map(&:value)
    expected = { 'lets' => src(11), 'class' => src(0, 1), 'tests' => src(10, 12), 'hiiro' => src(13) }
    runs.each do |group, (out, _err, status)|
      assert_equal [report('cart.rb', *expected[group]), 0], [out, status.exitstatus], group
    end
  end
end
