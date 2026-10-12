require 'test_helper'

class HomeTest < Minitest::Test
  def test_home_path_ignores_ambiguous_task_directory_and_keeps_absolute_output
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      home = File.join(root, 'home')
      cwd = File.join(root, 'code')
      FileUtils.mkdir_p([home, cwd])
      records = %w[home-mount-alpha home-mount-beta].map do |name|
        Hiiro::TaskRecord.create(name: name, primary_directory: cwd)
      end
      harness = Hiiro::TestHarness.load_bin('bin/h-home')
      Dir.stub(:home, home) do
        Dir.chdir(cwd) do
          output, = capture_io { harness.run_subcmd(:path) }
          assert_equal home, output
          absolute, = capture_io { harness.run_subcmd(:abspath) }
          assert_equal home, absolute
        end
      end
    ensure
      records&.each(&:destroy)
    end
  end
end
