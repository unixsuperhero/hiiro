require 'open3'
require 'shellwords'

class Hiiro
  class Rbenv
    class << self
      # --- Version queries ---

      # All installed rbenv versions (bare list, one per line).
      def versions
        `rbenv versions --bare`.lines(chomp: true)
      end
      alias all_versions versions

      # The currently active version (respects RBENV_VERSION, .ruby-version, global).
      def current_version
        `rbenv version-name`.strip
      end

      # The global default version.
      def global_version
        `rbenv global`.strip
      end

      # The local .ruby-version if one exists in the current directory tree, else nil.
      def local_version
        out = `rbenv local 2>/dev/null`.strip
        out.empty? ? nil : out
      end

      # True if the given version is installed.
      def has_version?(ver)
        versions.include?(ver.to_s)
      end

      # Full `ruby --version` string for the given version.
      def ruby_version(version: current_version)
        capture('ruby', '--version', version: version).strip
      end

      # --- Running commands ---

      # Run a command through `rbenv exec` in the given version.
      # Returns the exit status (true/false) like Kernel#system.
      def run(*cmd, version: current_version)
        system({ 'RBENV_VERSION' => version.to_s }, 'rbenv', 'exec', *cmd)
      end

      # Run a command through `rbenv exec` and capture stdout. Returns the output string.
      def capture(*cmd, version: current_version)
        out, = Open3.capture2({ 'RBENV_VERSION' => version.to_s }, 'rbenv', 'exec', *cmd)
        out
      end

      # Run a command in every installed version. Yields (version, success) if a block given.
      def run_in_all(*cmd)
        versions.each do |ver|
          puts "VERSION: #{ver}"
          success = run(*cmd, version: ver)
          yield ver, success if block_given?
        end
      end

      # --- Gem helpers ---

      # True if the named gem is installed in the given version.
      def gem_installed?(gem_name, version: current_version)
        !capture('gem', 'list', gem_name, version: version).strip.empty?
      end

      # Install or update a gem in the given version.
      # Passes --clear-sources --source rubygems.org to bypass the local index cache.
      def install_gem(gem_name, version: current_version, pre: false)
        source_flags = ['--clear-sources', '--source', 'https://rubygems.org']
        pre_flag     = pre ? ['--pre'] : []
        if gem_installed?(gem_name, version: version)
          run('gem', 'update', gem_name, *source_flags, *pre_flag, version: version)
        else
          run('gem', 'install', gem_name, *source_flags, *pre_flag, version: version)
        end
      end

      # Install or update a gem across all installed versions.
      def install_gem_in_all(gem_name, pre: false)
        versions.each { |ver| install_gem(gem_name, pre: pre, version: ver) }
      end

      # --- Path helpers ---

      # Absolute path to the rbenv shim (or versioned binary) for a command.
      def which(cmd, version: current_version)
        capture('which', cmd, version: version).strip
      end
    end
  end
end
