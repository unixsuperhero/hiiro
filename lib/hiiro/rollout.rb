require 'json'
require 'net/http'
require 'open3'

class Hiiro
  # Puts a hiiro release on rbenv Rubies: one gem install per compatible Ruby,
  # then one shared-assets apply (`h setup --apply`) run by the Ruby holding
  # the newest installed hiiro. Publishing stays in script/publish.
  class Rollout
    GemInstall = Struct.new(:ruby, :ok, :version, keyword_init: true)

    attr_reader :rbenv, :out, :gem_name

    def initialize(rbenv: Hiiro::Rbenv, out: $stdout, gem_name: 'hiiro')
      @rbenv = rbenv
      @out = out
      @gem_name = gem_name
    end

    # all: every installed Ruby, else the current one. Returns true when every
    # compatible Ruby installed the gem and the shared apply succeeded.
    def update(all: false, pre: false, expected: nil)
      rubies = all ? rbenv.versions : [rbenv.current_version]
      supported, skipped = rubies.partition { |ruby| rbenv.supported_ruby?(ruby) }
      out.puts "Updating #{gem_name} in #{supported.size} compatible Ruby version(s)"
      skipped.each { |ruby| out.puts "  ruby #{ruby}  skipped (requires Ruby #{Hiiro::SUPPORTED_RUBY_VERSION})" }

      installs = install_gems(supported, pre:)
      installs.each do |result|
        status = result.ok ? '' : '  (gem install failed)'
        status += "  (expected #{expected})" if expected && result.version != expected
        out.puts "  ruby #{result.ruby}  →  #{gem_name} #{result.version || '(not installed)'}#{status}"
      end

      source = shared_source(installs)
      unless source
        out.puts 'Shared assets: unchanged (no Ruby has the gem installed)'
        return false
      end

      out.puts "Shared assets: #{gem_name} #{source.version} from ruby #{source.ruby}"
      applied = rbenv.run('h', 'setup', '--apply', version: source.ruby)
      installs.all? { |result| result.ok && (expected.nil? || result.version == expected) } && applied ? true : false
    end

    def install_gems(rubies, pre: false)
      rubies.map { |ruby|
        Thread.new do
          ok = rbenv.install_gem(gem_name, pre:, version: ruby) ? true : false
          GemInstall.new(ruby:, ok:, version: rbenv.gem_version(gem_name, version: ruby))
        end
      }.map(&:value)
    end

    # The newest installed version; among equals, the first Ruby listed.
    def shared_source(installs)
      installs.select(&:version).max_by.with_index { |result, i| [Gem::Version.new(result.version), -i] }
    end

    # Release availability on rubygems.org: the versions API and the gem index
    # both have to list a version before `gem install` can see it.
    class RubyGems
      def initialize(gem_name = 'hiiro', fetch: ->(uri) { Net::HTTP.get(uri) },
                     search: ->(*argv) { Open3.capture2('gem', *argv).first })
        @gem_name = gem_name
        @fetch = fetch
        @search = search
      end

      def versions
        JSON.parse(@fetch.call(URI("https://rubygems.org/api/v1/versions/#{@gem_name}.json"))).map { |v| v['number'] }
      end

      def indexed_versions(pre: false)
        line = @search.call('search', '--remote', '--exact', '--all', *(pre ? ['--pre'] : []), @gem_name)
                      .lines.find { |l| l.start_with?("#{@gem_name} (") }
        line ? line[/\((.*)\)/, 1].split(', ').map { |v| v.split(' ').first } : []
      end

      def available?(version)
        versions.include?(version) && indexed_versions(pre: version.include?('.pre.')).include?(version)
      end

      def wait_for(version, attempts: 40, out: $stdout, sleeper: ->(seconds) { sleep(seconds) })
        attempts.times do |attempt|
          sleeper.call(attempt.zero? ? 5 : 15)
          begin
            return true if available?(version)

            out.puts "Waiting for v#{version} on RubyGems (attempt #{attempt + 1}/#{attempts})..."
          rescue StandardError => e
            out.puts "RubyGems poll error: #{e.message}"
          end
        end
        false
      end
    end
  end
end
