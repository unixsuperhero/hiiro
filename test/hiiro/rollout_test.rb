require_relative "../test_helper"
require "stringio"

class RolloutTest < Minitest::Test
  # Rubies, compatibility, gem install results, and installed versions are
  # data; every call is recorded.
  class FakeRbenv
    attr_reader :calls

    def initialize(rubies:, unsupported: [], failing: [], after: {}, before: {})
      @rubies, @unsupported, @failing, @after, @before = rubies, unsupported, failing, after, before
      @installed = {}
      @calls = []
      @lock = Mutex.new
    end

    def versions = @rubies
    def current_version = @rubies.last
    def supported_ruby?(ruby) = !@unsupported.include?(ruby)

    def install_gem(name, pre:, version:)
      log([:install, name, pre, version])
      return false if @failing.include?(version)

      @lock.synchronize { @installed[version] = true }
    end

    def gem_version(_name, version:) = @lock.synchronize { @installed[version] } ? @after[version] : @before[version]

    def run(*cmd, version:)
      log([:run, *cmd, version])
      true
    end

    private def log(call) = @lock.synchronize { @calls << call }
  end

  def test_each_ruby_installs_independently_and_shared_assets_apply_once_from_the_newest
    rbenv = FakeRbenv.new(rubies: %w[2.7.8 3.3.10 3.4.9 3.5.0], unsupported: %w[2.7.8], failing: %w[3.4.9],
                          after: { "3.3.10" => "0.1.394", "3.5.0" => "0.1.394" }, before: { "3.4.9" => "0.1.390" })
    out = StringIO.new

    ok = Hiiro::Rollout.new(rbenv:, out:).update(all: true, pre: true)

    refute ok
    assert_equal <<~OUT, out.string
      Updating hiiro in 3 compatible Ruby version(s)
        ruby 2.7.8  skipped (requires Ruby #{Hiiro::SUPPORTED_RUBY_VERSION})
        ruby 3.3.10  →  hiiro 0.1.394
        ruby 3.4.9  →  hiiro 0.1.390  (gem install failed)
        ruby 3.5.0  →  hiiro 0.1.394
      Shared assets: hiiro 0.1.394 from ruby 3.3.10
    OUT
    assert_equal [[:install, "hiiro", true, "3.3.10"], [:install, "hiiro", true, "3.4.9"], [:install, "hiiro", true, "3.5.0"]],
                 rbenv.calls.select { |c| c.first == :install }.sort_by(&:last)
    assert_equal [[:run, "h", "setup", "--apply", "3.3.10"]], rbenv.calls.select { |c| c.first == :run }
  end

  def test_success_needs_every_ruby_on_the_expected_version
    rbenv = FakeRbenv.new(rubies: %w[3.3.10 3.4.9], after: { "3.3.10" => "0.1.394", "3.4.9" => "0.1.395" })
    out = StringIO.new

    assert Hiiro::Rollout.new(rbenv:, out:).update(all: true)
    refute Hiiro::Rollout.new(rbenv:, out: out = StringIO.new).update(all: true, expected: "0.1.395")
    assert_includes out.string, "  ruby 3.3.10  →  hiiro 0.1.394  (expected 0.1.395)\n"
    assert_includes out.string, "Shared assets: hiiro 0.1.395 from ruby 3.4.9\n"
  end

  def test_without_all_only_the_current_ruby_is_installed_and_nothing_applies_when_no_gem_is_present
    rbenv = FakeRbenv.new(rubies: %w[3.3.10 3.4.9], failing: %w[3.4.9])
    out = StringIO.new

    refute Hiiro::Rollout.new(rbenv:, out:).update
    assert_equal [[:install, "hiiro", false, "3.4.9"]], rbenv.calls
    assert_equal "Shared assets: unchanged (no Ruby has the gem installed)\n", out.string.lines.last
  end

  def test_rubygems_waits_for_both_the_api_and_the_gem_index
    api = [%w[0.1.393], %w[0.1.394 0.1.393], %w[0.1.394 0.1.393]]
    index = ["hiiro (0.1.393)\n", "*** REMOTE GEMS ***\n\nhiiro (0.1.394 ruby, 0.1.393)\n"]
    searches = []
    rubygems = Hiiro::Rollout::RubyGems.new(fetch: ->(uri) { api.shift.map { |n| { number: n } }.to_json.tap { assert_equal "/api/v1/versions/hiiro.json", uri.path } },
                                            search: ->(*argv) { searches << argv; index.shift })
    slept = []
    out = StringIO.new

    assert rubygems.wait_for("0.1.394", out:, sleeper: ->(s) { slept << s })
    assert_equal [5, 15, 15], slept
    assert_equal "Waiting for v0.1.394 on RubyGems (attempt 1/40)...\nWaiting for v0.1.394 on RubyGems (attempt 2/40)...\n", out.string
    assert_equal [%w[search --remote --exact --all hiiro]] * 2, searches
  end

  def test_rubygems_gives_up_after_its_attempts_and_reports_poll_errors
    rubygems = Hiiro::Rollout::RubyGems.new(fetch: ->(_) { raise SocketError, "offline" }, search: ->(*) { "" })
    out = StringIO.new

    refute rubygems.wait_for("0.1.394.pre.1", attempts: 2, out:, sleeper: ->(_) {})
    assert_equal "RubyGems poll error: offline\nRubyGems poll error: offline\n", out.string
  end
end
