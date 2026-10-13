class Hiiro
  # The root `h` commands. exe/h runs them; `h bin` reads the same registrations
  # (without running any handler) so its listing, edit targets, completion, and
  # docs match what `h` dispatches.
  module RootCommands
    # The prefix installed commands get: `h setup` installs h-NAME, `hiiro setup` hiiro-NAME.
    def self.setup_prefix = File.basename($0).split('-').first

    def self.register(hiiro)
      hiiro.instance_eval do
        add_flag(:all, short: :a, desc: 'Show the version of hiiro for all versions of ruby installed')

        add_cmd(:version, opts: %i[all]) { |*args|
          if @opts.all
            Hiiro::Rbenv.versions.each do |ver|
              output = Hiiro::Rbenv.capture('h', 'version', version: ver).strip
              puts "ruby v#{ver} => #{output}"
            end
          else
            puts Hiiro::VERSION
          end
        }

        add_subcmd(:ping) { |*args|
          puts "pong"
        }

        add_subcmd(:install, :update) { |*args|
          opts = Hiiro::Options.setup {
            flag(:all, short: :a, desc: 'Every compatible rbenv Ruby')
            flag(:pre, short: :p, desc: 'Allow a pre-release')
            option(:wait, short: :w, desc: 'Wait until VERSION is on RubyGems first')
            flag(:notify, short: :n, desc: 'Report the outcome with terminal-notifier')
          }.parse!(args)
          notify = ->(title, message) { system('terminal-notifier', '-title', title, '-message', message) if opts.notify }

          if opts.wait
            puts "Waiting for v#{opts.wait} on RubyGems..."
            unless Hiiro::Rollout::RubyGems.new.wait_for(opts.wait)
              notify.call('hiiro update failed', "Timed out waiting for v#{opts.wait} on RubyGems")
              exit 1
            end
          end

          pre = opts.pre || opts.wait.to_s.include?('.pre.')
          ok = Hiiro::Rollout.new.update(all: opts.all, pre:, expected: opts.wait)
          notify.call(ok ? 'hiiro updated' : 'hiiro update incomplete', ok ? "v#{opts.wait || 'latest'} installed" : 'See `h check_version -a`')
          exit(ok ? 0 : 1)
        }

        add_subcmd(:setup) do |*args|
          exit Hiiro::Install.cli(args, prefix: RootCommands.setup_prefix)
        end

        add_subcmd(:alert) do |*args|
          Hiiro::Notification.show(self)
        end

        add_subcmd(:queue) do |*args|
          Hiiro::Queue.build_hiiro(self, args: args).run
        end

        add_subcmd(:service, :svc) do |*svc_args|
          sm = Hiiro::ServiceManager.new(context: -> { context })
          Hiiro::ServiceManager.build_hiiro(this, sm, context: -> { context }, args: svc_args).run
        end

        add_subcmd(:run) do |*run_args|
          rt = Hiiro::RunnerTool.new(context: -> { context })
          Hiiro::RunnerTool.build_hiiro(this, rt, context: -> { context }, args: run_args).run
        end

        add_subcmd(:file) do |*file_args|
          af = Hiiro::AppFiles.new(context: -> { context })
          Hiiro::AppFiles.build_hiiro(this, af, context: -> { context }, args: file_args).run
        end

        add_subcmd(:check_version) do |*args|
          opts = Hiiro::Options.setup {
            flag(:all, short: :a, desc: 'Check all rbenv versions')
          }.parse!(args)

          expected = opts.args.first
          versions = opts.all ? Hiiro::Rbenv.versions : [Hiiro::Rbenv.current_version]

          mismatched = 0
          versions.each do |ver|
            actual = Hiiro::Rbenv.gem_version('hiiro', version: ver)
            ok = expected.nil? || actual == expected
            mismatched += 1 unless ok
            status = ok ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"
            puts "  #{status} ruby #{ver}: hiiro #{actual || '(not installed)'}"
          end

          exit(mismatched == 0 ? 0 : 1)
        end

        add_subcmd(:delayed_update) do |*args|
          expected = args.first
          unless expected
            puts "Usage: h delayed_update <expected_version>"
            next
          end

          system('h', 'bg', 'run', 'h', 'update', '--all', '--notify', '--wait', expected)
        end

        add_subcmd(:rnext) do |*args|
          system('git', 'rnext', *args)
        end
      end
    end

    # A root instance with every registration and nothing run or recorded.
    def self.build(bin_name = 'h')
      Hiiro.new(bin_name, cwd: Dir.pwd).tap do |root|
        root.register_builtins
        register(root)
      end
    end
  end
end
