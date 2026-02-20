require "test_helper"

class AppTest < Minitest::Test
  def setup
    @harness = Hiiro::TestHarness.load_bin("bin/h-app") do
      # Stub the top-level helper methods
      define_singleton_method(:load_apps) { { "frontend" => "apps/frontend", "api" => "services/api" } }
      define_singleton_method(:save_apps) { |apps| @saved_apps = apps }
      define_singleton_method(:task_root) { "/home/user/work/my-task" }
      define_singleton_method(:relative_cd_path) { |path| path }
      define_singleton_method(:send_cd) { |path| @cd_path = path }

      # Stub git helper
      define_singleton_method(:git) { MockGit.new }

      # Stub environment
      define_singleton_method(:environment) { MockEnvironment.new }
    end
  end

  def test_registers_expected_subcommands
    expected = %i[config cd ls path abspath add rm remove]
    expected.each do |subcmd|
      assert @harness.has_subcmd?(subcmd), "Expected subcmd :#{subcmd} to be registered"
    end
  end

  def test_config_opens_editor
    @harness.run_subcmd(:config)

    assert_equal 1, @harness.system_calls.size
    call = @harness.system_calls.first
    assert_includes call.last, 'apps.yml'
  end

  class MockGit
    def root
      "/home/user/work/my-task"
    end
  end

  class MockEnvironment
    def all_apps
      [MockApp.new("frontend", "apps/frontend"), MockApp.new("api", "services/api")]
    end

    def app_matcher
      MockMatcher.new(all_apps)
    end
  end

  class MockApp
    attr_reader :name, :relative_path

    def initialize(name, path)
      @name = name
      @relative_path = path
    end
  end

  class MockMatcher
    def initialize(apps)
      @apps = apps
    end

    def find(name)
      MockResult.new(@apps.select { |a| a.name.start_with?(name) })
    end
  end

  class MockResult
    def initialize(matches)
      @matches = matches
    end

    def match?
      @matches.any?
    end

    def first
      MockItem.new(@matches.first) if @matches.any?
    end
  end

  class MockItem
    attr_reader :item

    def initialize(item)
      @item = item
    end
  end
end
