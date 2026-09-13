require "test_helper"
require "hiiro/options"
require "hiiro/notification"
require "json"
require "timeout"

class NotificationTest < Minitest::Test
  include TestHelpers

  # Mock hiiro object for testing
  class MockHiiroForNotify
    attr_accessor :args

    def initialize(args = [])
      @args = args
    end
  end

  def test_initialize_captures_args
    hiiro = MockHiiroForNotify.new(['-m', 'test message'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal ['-m', 'test message'], notification.original_args
  end

  def test_initialize_dups_args
    args = ['-m', 'test']
    hiiro = MockHiiroForNotify.new(args)
    notification = Hiiro::Notification.new(hiiro)

    args << '--extra'
    refute_includes notification.original_args, '--extra'
  end

  def test_options_parses_message
    hiiro = MockHiiroForNotify.new(['-m', 'Hello World'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'Hello World', notification.options.message
  end

  def test_options_parses_title
    hiiro = MockHiiroForNotify.new(['-t', 'My Title'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'My Title', notification.options.title
  end

  def test_options_parses_sound
    hiiro = MockHiiroForNotify.new(['-s', 'ping'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'ping', notification.options.sound
  end

  def test_options_parses_link
    hiiro = MockHiiroForNotify.new(['-l', 'https://example.com'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'https://example.com', notification.options.link
  end

  def test_options_parses_command
    hiiro = MockHiiroForNotify.new(['-c', 'open .'])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'open .', notification.options.command
  end

  def test_options_default_sound
    hiiro = MockHiiroForNotify.new([])
    notification = Hiiro::Notification.new(hiiro)

    assert_equal 'basso', notification.options.sound
  end

  def test_sounds_returns_hash
    hiiro = MockHiiroForNotify.new([])
    notification = Hiiro::Notification.new(hiiro)

    assert_kind_of Hash, notification.sounds
  end

  def test_sounds_looks_in_config_directory
    with_temp_dir do |dir|
      # Create mock sound files
      sound_dir = File.join(dir, '.config/hiiro/sounds')
      FileUtils.mkdir_p(sound_dir)
      File.write(File.join(sound_dir, 'custom.mp3'), '')
      File.write(File.join(sound_dir, 'alert.wav'), '')

      hiiro = MockHiiroForNotify.new([])
      notification = Hiiro::Notification.new(hiiro)

      # Stub Dir.home to return our temp dir
      Dir.stub(:home, dir) do
        sounds = notification.sounds

        # Should have keys for both sounds (lowercased basenames)
        assert_includes sounds.keys, 'custom'
        assert_includes sounds.keys, 'alert'
      end
    end
  end

  def test_show_runs_notification_and_sound_without_herdr_terminals
    with_temp_dir do |dir|
      previous_env = ENV.to_h
      script = <<~RUBY
        \#!#{RbConfig.ruby}
        require "json"
        path = File.join(#{dir.inspect}, File.basename($0) + ".json")
        File.write(path + ".tmp", JSON.generate(ARGV))
        File.rename(path + ".tmp", path)
        puts '{"result":{}}'
      RUBY
      %w[terminal-notifier afplay herdr].each do |name|
        path = File.join(dir, name)
        File.write(path, script)
        FileUtils.chmod(0o755, path)
      end
      sound_dir = File.join(dir, ".config/hiiro/sounds")
      FileUtils.mkdir_p(sound_dir)
      sound_path = File.join(sound_dir, "done.wav")
      File.write(sound_path, "")
      ENV.update("PATH" => "#{dir}:#{ENV['PATH']}", "HERDR_ENV" => "1")
      notification = Hiiro::Notification.new(MockHiiroForNotify.new(["-m", "Work completed", "-s", "done"]))

      Dir.stub(:home, dir) { notification.show }

      refute File.exist?(File.join(dir, "herdr.json")), "A notification must not allocate Herdr terminals"
      Timeout.timeout(5) do
        sleep 0.01 until %w[terminal-notifier afplay].all? { |name| File.exist?(File.join(dir, "#{name}.json")) }
      end
      assert_equal ["-message", "Work completed"], JSON.parse(File.read(File.join(dir, "terminal-notifier.json")))
      assert_equal [sound_path], JSON.parse(File.read(File.join(dir, "afplay.json")))
    ensure
      ENV.replace(previous_env)
    end
  end

  def test_show_class_method
    hiiro = MockHiiroForNotify.new(['-m', 'test'])

    # Stub instance method to verify class method delegates
    called = false
    Hiiro::Notification.stub(:new, ->(h) {
      mock = Object.new
      mock.define_singleton_method(:show) { called = true }
      mock
    }) do
      Hiiro::Notification.show(hiiro)
    end

    assert called, "Expected show to be called on instance"
  end
end
