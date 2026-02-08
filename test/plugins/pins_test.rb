require "test_helper"
require_relative "../../plugins/pins"

class PinsPinTest < Minitest::Test
  include TestHelpers

  def setup
    @mock_hiiro = MockHiiro.new
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
      assert File.exist?(pin.pin_file)

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

  def test_pin_file_creation
    with_temp_dir do |dir|
      pin = create_pin_with_dir(dir)

      # Accessing pins should create file
      pin.pins

      assert File.exist?(pin.pin_file)
    end
  end

  private

  def create_pin_with_dir(dir)
    mock_hiiro = MockHiiro.new("test-bin")
    pin = Pins::Pin.new(mock_hiiro)

    # Override pin_dir to use temp directory
    pin.define_singleton_method(:pin_dir) { dir }

    pin
  end

  class MockHiiro
    attr_reader :bin_name

    def initialize(bin_name = "h")
      @bin_name = bin_name
    end
  end
end
