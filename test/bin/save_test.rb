require_relative "../test_helper"
require "open3"
require "rbconfig"

class SaveTest < Minitest::Test
  def test_same_second_and_prefix_never_overwrite_existing_content
    Dir.mktmpdir do |home|
      env = { "HOME" => home, "HIIRO_TEST_DB" => "sqlite::memory:" }
      script = <<~RUBY
        require 'time'
        fixed = Time.local(2026, 9, 15, 12, 34, 56)
        Time.define_singleton_method(:now) { fixed }
        load #{File.expand_path('../../bin/h-save', __dir__).inspect}
      RUBY
      paths = ["hello world", "hello wonderful"].map do |text|
        output, error, status = Open3.capture3(
          env, RbConfig.ruby, "-I", File.expand_path('../../lib', __dir__),
          "-e", script, "--", text
        )
        assert status.success?, error
        output.strip
      end
      assert_equal ["20260915123456-hello-wo.txt", "20260915123456-hello-wo-2.txt"],
        paths.map { |path| File.basename(path) }
      assert_equal ["hello world", "hello wonderful"], paths.map { |path| File.binread(path) }
      assert paths.all? { |path| File.dirname(path) == File.join(home, "saved") }
    end
  end
end
