require 'test_helper'
require 'open3'
require 'rbconfig'

class PrAttachTest < Minitest::Test
  def test_attach_bare_tracked_number_writes_executable_launcher_without_native_launch
    root = File.expand_path('../..', __dir__)
    Dir.mktmpdir('hiiro-pr-attach-') do |dir|
      workdir = File.join(dir, 'workspace with spaces')
      FileUtils.mkdir_p(workdir)
      fixture = File.join(dir, 'adapters.rb')
      File.write(fixture, <<~RUBY)
        require 'hiiro'
        require #{File.join(root, 'plugins/pins.rb').inspect}
        Hiiro::DB.setup!
        Hiiro::PinnedPr.create(number: 7, repo: 'team/one', pinned: true,
          head_ref_name: 'feature/pr', task: 'fixture-task')

        class Environment
          def self.current = new
          def find_task(name)
            raise 'unexpected task' unless name == 'fixture-task'
            tree = Struct.new(:path).new(ENV.fetch('ATTACH_WORK_DIR'))
            Struct.new(:session_name, :tree).new('fixture-workspace', tree)
          end
        end

        class FixtureHerdr
          def find_workspace(name)
            raise 'unexpected workspace' unless name == 'fixture-workspace'
            'controlled-workspace'
          end

          def new_tab(**options)
            raise 'unexpected workspace selection' unless options.fetch(:workspace) == 'controlled-workspace'
            path = options.fetch(:command)
            puts JSON.dump({ executable: File.executable?(path), script: File.read(path) })
          ensure
            File.unlink(path) if path && File.file?(path)
          end
        end

        class Hiiro
          def herdr_client = FixtureHerdr.new
        end

        module Kernel
          def system(*) = raise('native process launch forbidden')
          def spawn(*) = raise('native process launch forbidden')
          def `(command) = raise('native process launch forbidden')
        end
        def Process.spawn(*) = raise('native process launch forbidden')
        def IO.popen(*) = raise('native process launch forbidden')
      RUBY
      environment = {
        'HOME' => dir,
        'HIIRO_TEST_DB' => "sqlite://#{File.join(dir, 'records.db')}",
        'ATTACH_WORK_DIR' => workdir,
      }
      stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby,
        '-I', File.join(root, 'lib'), '-r', fixture, File.join(root, 'bin/h-pr'), 'attach', '7')
      assert status.success?, stderr
      result = JSON.parse(stdout)
      assert_equal true, result.fetch('executable')
      assert_includes result.fetch('script').lines.map(&:chomp), "cd #{Shellwords.shellescape(workdir)}"
      assert_includes result.fetch('script').lines.map(&:chomp), 'git checkout feature/pr'
    end
  end
end
