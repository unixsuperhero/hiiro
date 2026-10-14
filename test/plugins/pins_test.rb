require "test_helper"
require_relative "../../plugins/pins"

class PinsPinTest < Minitest::Test
  include TestHelpers

  def setup
    @mock_hiiro = MockHiiro.new
    Hiiro::RegistryEntry.dataset.delete
  end

  def teardown
    Hiiro::RegistryEntry.dataset.delete
  end

  def test_pin_set_and_get
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)

      pin.set("my_key", "my_value")
      assert_equal "my_value", pin.pins["my_key"]
    end
  end

  def test_pin_set_and_save
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)

      result = pin.set_and_save("test_key", "test_value")

      assert_equal "test_value", result
      assert_equal "test_value", Hiiro::Table.named("test-bin").find("test_key").value

      # Reload and verify
      pin.pins!
      assert_equal "test_value", pin.get("test_key")
    end
  end

  def test_pin_find_with_prefix
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)
      pin.set("apple", "1")
      pin.set("apricot", "2")
      pin.set("banana", "3")
      pin.save_pins

      assert_equal "apple", pin.find("ap")
    end
  end

  def test_pin_find_all_with_prefix
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)
      pin.set("apple", "1")
      pin.set("apricot", "2")
      pin.set("banana", "3")
      pin.save_pins

      result = pin.find_all("ap")
      assert_includes result, "apple"
      assert_includes result, "apricot"
      refute_includes result, "banana"
    end
  end

  def test_pin_remove_single_match
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)
      pin.set("unique_key", "value")
      pin.save_pins

      pin.remove("unique")

      refute pin.pins.key?("unique_key")
    end
  end

  def test_pin_remove_and_save
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)
      pin.set("to_remove", "value")
      pin.save_pins

      pin.remove_and_save("to_remove")

      # Reload and verify
      pin.pins!
      assert_nil pin.get("to_remove")
    end
  end

  def test_pin_get_with_exact_key
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)
      pin.set("exact_key", "exact_value")
      pin.save_pins

      assert_equal "exact_value", pin.get("exact_key")
    end
  end

  def test_pins_live_in_the_table_named_after_the_command
    pin = Pins::Pin.new(MockHiiro.new("h-sha"))
    pin.set_and_save("102", "4fb3cff")

    assert_equal "sha", pin.table_name
    assert_equal [["102", "4fb3cff"]], Hiiro::Table.named("sha").entries.map { |e| [e.name, e.value] }
    assert_equal({ "102" => "4fb3cff" }, Pins::Pin.new(MockHiiro.new("h-sha")).pins)
  end

  private

  def create_pin_with_dir(dir)
    Pins::Pin.new(MockHiiro.new("test-bin"))
  end

  class MockHiiro
    attr_reader :bin_name

    def initialize(bin_name = "h")
      @bin_name = bin_name
    end
  end
end
