require "test_helper"
require_relative "../../plugins/pins"

class PinsPinTest < Minitest::Test
  include TestHelpers

  def setup
    Hiiro::PinRecord.where(command: 'pins-test').delete
    @pin = Pins::Pin.new(MockHiiro.new('pins-test'))
  end

  def teardown
    Hiiro::PinRecord.where(command: 'pins-test').delete
  end

  def test_set_is_persisted_and_reads_preserve_string_types
    assert_equal '42', @pin.set('number_text', '42')
    @pin.set('boolean_text', 'false')
    @pin.set('json_text', '[1,2]')
    reloaded = Pins::Pin.new(MockHiiro.new('pins-test'))
    assert_equal({ 'number_text' => '42', 'boolean_text' => 'false', 'json_text' => '[1,2]' }, reloaded.pins)
  end

  def test_prefix_search_and_exact_get
    @pin.set('apple', '1')
    @pin.set('apricot', '2')
    @pin.set('banana', '3')
    assert_equal 'apple', @pin.find('ap')
    assert_equal %w[apple apricot], @pin.find_all('ap')
    assert_equal '2', @pin.get('apricot')
  end

  def test_stale_read_does_not_delete_or_rewrite_another_writer
    @pin.set('first', 'old')
    original_id = Hiiro::PinRecord.find_key('pins-test', 'first').id
    stale = Pins::Pin.new(MockHiiro.new('pins-test'))
    snapshot = stale.pins
    @pin.set('other', 'keep')
    @pin.set('first', 'new')
    stale.set('third', 'added')
    snapshot.delete('first')
    assert_equal({ 'first' => 'new', 'other' => 'keep', 'third' => 'added' }, stale.pins)
    assert_equal original_id, Hiiro::PinRecord.find_key('pins-test', 'first').id
    stale.remove('third')
    assert_equal({ 'first' => 'new', 'other' => 'keep' }, @pin.pins)
  end

  def test_remove_resolves_only_selected_key_and_rejects_ambiguous_prefix
    @pin.set('apple', '1')
    @pin.set('apricot', '2')
    @pin.set('banana', '3')
    capture_io { @pin.remove('ap') }
    assert_equal({ 'apple' => '1', 'apricot' => '2', 'banana' => '3' }, @pin.pins)
    assert_equal '1', @pin.remove('apple')
    assert_equal({ 'apricot' => '2', 'banana' => '3' }, @pin.pins)
    assert_equal '3', @pin.remove('ban')
    assert_equal({ 'apricot' => '2' }, @pin.pins)
  end

  def test_legacy_file_is_not_read_or_changed
    with_temp_dir do |dir|
      path = File.join(dir, 'pins-test')
      original = "file_only: legacy\n"
      File.write(path, original)
      Hiiro::Config.stub(:config_dir, dir) do
        @pin.set('database_only', 'live')
        assert_equal({ 'database_only' => 'live' }, @pin.pins)
        assert_equal original, File.read(path)
        assert_equal ['pins-test'], Dir.children(dir)
      end
    end
  end

  def test_database_errors_propagate_without_losing_existing_values
    @pin.set('retained', 'keep')
    error = Sequel::DatabaseError.new('unavailable')
    Hiiro::PinRecord.stub(:for_command, ->(*) { raise error }) do
      assert_raises(Sequel::DatabaseError) { @pin.pins }
    end
    Hiiro::PinRecord.stub(:set, ->(*) { raise error }) do
      assert_raises(Sequel::DatabaseError) { @pin.set('retained', 'changed') }
    end
    assert_equal({ 'retained' => 'keep' }, @pin.pins)
  end
end
