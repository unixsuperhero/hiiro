require_relative "../test_helper"

class BinsTest < Minitest::Test
  def test_require_hiiro_loads_bins_helper
    assert defined?(Hiiro::Bins)
  end

  def test_glob_finds_executables_from_path
    Dir.mktmpdir do |dir|
      executable = File.join(dir, "h-example")
      non_executable = File.join(dir, "h-hidden")
      File.write(executable, "#!/bin/sh\n")
      File.write(non_executable, "#!/bin/sh\n")
      FileUtils.chmod("+x", executable)

      with_path(dir) do
        assert_equal [executable], Hiiro::Bins.glob("h-*")
      end
    end
  end

  def test_all_lists_all_executables_on_path
    Dir.mktmpdir do |dir|
      executable = File.join(dir, "anything")
      File.write(executable, "#!/bin/sh\n")
      FileUtils.chmod("+x", executable)

      with_path(dir) do
        assert_includes Hiiro::Bins.all, executable
      end
    end
  end

  private

  def with_path(path)
    original = ENV['PATH']
    ENV['PATH'] = path
    yield
  ensure
    ENV['PATH'] = original
  end
end
