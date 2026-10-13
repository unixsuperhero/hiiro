require 'sequel'
require 'yaml'
require 'time'
require 'date'
require 'shellwords'
require 'fileutils'
require 'rbconfig'
require 'open3'
require 'cgi'

class Hiiro
  # Where each schedule stands: whether it is registered with launchd and which
  # occurrence it last finished. Written only by Schedule (enable/disable/tick).
  #
  #   { definition: 'reminders', label: 'com.hiiro.schedule.reminders', enabled: true,
  #     enabled_at: '…', disabled_at: nil, last_due: '2026-10-13T12:00:00Z', last_due_at: '…',
  #     last_run_id: 'run-…', last_outcome: 'completed', detail: nil, updated_at: '…' }
  class ScheduleCheckpoint < Sequel::Model(:schedule_checkpoints)
    def self.create_table!(db)
      db.create_table?(:schedule_checkpoints) do
        primary_key :id
        String :definition, null: false, unique: true
        String :label
        TrueClass :enabled, null: false, default: false
        String :enabled_at
        String :disabled_at
        String :last_due
        String :last_due_at
        String :last_run_id
        String :last_outcome
        String :detail
        String :updated_at
      end
    end

    def self.for(name) = first(definition: name)

    def self.write!(name, **values)
      values[:updated_at] = Time.now.utc.iso8601
      db.transaction(mode: :immediate) do
        where(definition: name).update(values).positive? || insert(values.merge(definition: name))
        first(definition: name)
      end
    end

    Hiiro::DB.register(self)
  end

  # Recurring work defined in ~/.config/hiiro/schedules.yml (and one loop recipe
  # per ~/ai/loops/NAME/config.yml), run one occurrence at a time by
  # `h schedule run NAME`, which is what an enabled launchd job invokes.
  module Schedule
    JOBS = %w[reminders queue pr-monitor command loop].freeze
    MISSED = %w[run_once skip].freeze
    NOTIFY = %w[never failures always].freeze
    BYPASS = /\A--(dangerously-skip-permissions|dangerously-bypass-approvals-and-sandbox|yolo)\z|bypassPermissions/
    ROOT = File.expand_path('../..', __dir__)
    LIB = File.join(ROOT, 'lib')

    def self.config_path = Config.path('schedules.yml')
    def self.loops_root = File.join(Dir.home, 'ai/loops')
    def self.hiiro_argv(*path) = [RbConfig.ruby, '-I', LIB, File.join(ROOT, *path)]

    # One occurrence of a definition: key is what claims and checkpoints compare.
    Occurrence = Struct.new(:key, :at, keyword_init: true)

    # A definition that failed validation; listed with its reason, never run.
    Invalid = Struct.new(:name, :error, :source, keyword_init: true)

    # A validated definition. program is an absolute argv; nothing here starts anything.
    #
    #   { name: 'nightly', job: 'command', recurrence: 'wall_clock', every: nil, at: [2, 30],
    #     timezone: 'America/New_York', missed: 'run_once', grace: 3600, max_concurrent: 1, timeout: 1800,
    #     program: ['/usr/local/bin/backup', '--quick'], cwd: '/Users/me/work', env: { 'FOO' => 'bar' },
    #     notify: 'failures', keep_logs: false, artifacts: ['out/report.txt'], agent: false, source: '…/schedules.yml' }
    Definition = Struct.new(:name, :job, :recurrence, :every, :at, :timezone, :missed, :grace, :max_concurrent,
      :timeout, :program, :cwd, :env, :notify, :keep_logs, :artifacts, :agent, :source, keyword_init: true) do
      def label(prefix = Launchd.prefix) = "#{prefix}.#{name}"
      def interval? = recurrence == 'interval'
      def command = CommandSpecification.new(*program, env: env, cwd: cwd)

      def recurrence_text
        return "every #{every}s" if interval?

        format('at %02d:%02d %s', *at, timezone)
      end

      # The latest occurrence at or before now.
      def due(now)
        if interval?
          slot = Time.at((now.to_i / every) * every).utc
          return Occurrence.new(key: slot.iso8601, at: slot)
        end

        Schedule.in_zone(timezone) do
          local = now.getlocal
          day = Date.new(local.year, local.month, local.day)
          at_time = Schedule.wall_time(day, *at)
          day -= 1 if at_time > now
          # The key names the configured wall-clock time, so a repeated (fall-back)
          # hour is one occurrence and a skipped (spring-forward) time still runs once.
          Occurrence.new(key: format('%s %02d:%02d %s', day.iso8601, *at, timezone), at: Schedule.wall_time(day, *at))
        end
      end

      def next_after(now)
        return Time.at((now.to_i / every + 1) * every).utc if interval?

        Schedule.in_zone(timezone) do
          local = now.getlocal
          day = Date.new(local.year, local.month, local.day)
          candidate = Schedule.wall_time(day, *at)
          candidate > now ? candidate : Schedule.wall_time(day + 1, *at)
        end
      end
    end

    class << self
      def in_zone(zone)
        return yield if zone == 'local'

        previous = ENV['TZ']
        ENV['TZ'] = zone
        yield
      ensure
        ENV['TZ'] = previous unless zone == 'local'
      end

      # A wall-clock time that occurs twice (DST fall-back) resolves to its first instant.
      def wall_time(day, hour, minute)
        time = Time.local(day.year, day.month, day.day, hour, minute)
        earlier = time - 3600
        [earlier.year, earlier.month, earlier.day, earlier.hour, earlier.min] == [day.year, day.month, day.day, hour, minute] ? earlier : time
      end

      # Every definition keyed by name: a Definition, or an Invalid with its reason.
      def definitions
        raw = File.exist?(config_path) ? YAML.safe_load_file(config_path) || {} : {}
        raise Error, "#{config_path}: expected a mapping of schedule names" unless raw.is_a?(Hash)

        sources = raw.map { |name, fields| [name.to_s, fields, config_path] }
        Loops.configs.each { |name, (path, config)| sources << ["loop-#{name}", Loops.fields(config), path] }
        sources.to_h do |name, fields, source|
          [name, build(name, fields, source: source)]
        rescue Error => e
          [name, Invalid.new(name: name, error: e.message, source: source)]
        end
      end

      def definition(name)
        found = definitions.fetch(name) { raise Error, "Unknown schedule #{name.inspect} (see h schedule ls)" }
        raise Error, found.error if found.is_a?(Invalid)

        found
      end

      def build(name, fields, source:)
        raise Error, "#{name}: expected a mapping" unless fields.is_a?(Hash)
        fields = fields.transform_keys(&:to_s)
        known = %w[job every at timezone missed grace max_concurrent timeout command args cwd env notify keep_logs
                   artifacts agent prompt max_running]
        unknown = fields.keys - known
        raise Error, "#{name}: unknown fields #{unknown.join(', ')}" unless unknown.empty?
        raise Error, "#{name}: invalid name" unless name.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/)

        job = fields.fetch('job') { raise Error, "#{name}: job is required (#{JOBS.join(', ')})" }
        raise Error, "#{name}: unknown job #{job.inspect} (#{JOBS.join(', ')})" unless JOBS.include?(job)
        if fields.key?('every') == fields.key?('at')
          raise Error, "#{name}: give exactly one of every: (interval) or at: (wall clock HH:MM)"
        end

        every = at = nil
        if fields.key?('every')
          every = Duration.parse(fields['every'].to_s)&.seconds&.to_i
          raise Error, "#{name}: every: must be a duration such as 30s, 5m, 1h" unless every&.positive?
        else
          match = fields['at'].to_s.match(/\A([01]\d|2[0-3]):([0-5]\d)\z/)
          raise Error, "#{name}: at: must be HH:MM (24-hour)" unless match
          at = [match[1].to_i, match[2].to_i]
        end
        timezone = fields.fetch('timezone', 'local').to_s
        unless timezone == 'local' || File.file?(File.join('/usr/share/zoneinfo', timezone))
          raise Error, "#{name}: unknown timezone #{timezone.inspect}"
        end
        missed = fields.fetch('missed', 'run_once').to_s
        raise Error, "#{name}: missed: must be #{MISSED.join(' or ')}" unless MISSED.include?(missed)
        notify = fields.fetch('notify', 'never').to_s
        raise Error, "#{name}: notify: must be #{NOTIFY.join(', ')}" unless NOTIFY.include?(notify)
        env = (fields['env'] || {})
        raise Error, "#{name}: env: must be a mapping" unless env.is_a?(Hash)
        env = env.to_h { |key, value| [key.to_s, value.to_s] }
        cwd = File.expand_path(fields.fetch('cwd', Dir.home).to_s)
        raise Error, "#{name}: cwd #{cwd} is not a directory" unless File.directory?(cwd)

        Definition.new(
          name: name, job: job, recurrence: every ? 'interval' : 'wall_clock', every: every, at: at, timezone: timezone,
          missed: missed, grace: duration(name, fields, 'grace', every || 3600),
          max_concurrent: positive(name, fields, 'max_concurrent', 1), timeout: duration(name, fields, 'timeout', 600),
          program: program(name, job, fields, env), cwd: cwd, env: env, notify: notify,
          keep_logs: fields.fetch('keep_logs', job == 'loop') == true, artifacts: Array(fields['artifacts']).map(&:to_s),
          agent: fields['agent'] ? true : false, source: source
        )
      end

      def duration(name, fields, key, default)
        return default unless fields.key?(key)

        Duration.parse(fields[key].to_s)&.seconds&.to_i.tap do |seconds|
          raise Error, "#{name}: #{key}: must be a duration such as 30s, 5m, 1h" unless seconds&.positive?
        end
      end

      def positive(name, fields, key, default)
        value = fields.fetch(key, default)
        raise Error, "#{name}: #{key}: must be a positive integer" unless value.is_a?(Integer) && value.positive?

        value
      end

      # Builtin jobs reuse the existing one-shot workers; command and loop jobs
      # name their own argv, whose executable is resolved to an absolute path now.
      def program(name, job, fields, env)
        argv = case job
        when 'reminders' then [*hiiro_argv('bin/h-remind'), 'check']
        when 'pr-monitor' then [*hiiro_argv('bin/h-pr-monitor'), '--once', *Array(fields['args']).map(&:to_s)]
        when 'queue'
          raise Error, "#{name}: a queue schedule launches agents; set agent: true to opt in" unless fields['agent'] == true

          [*hiiro_argv('exe/h'), 'queue', 'tick', '--max', positive(name, fields, 'max_running', 1).to_s]
        when 'command'
          command = fields['command']
          raise Error, "#{name}: command: must be a nonempty argv list" unless command.is_a?(Array) && !command.empty?

          command.map(&:to_s)
        when 'loop'
          agent = fields['agent']
          command = fields['command']
          if command
            raise Error, "#{name}: command: must be a nonempty argv list" unless command.is_a?(Array) && !command.empty?

            command.map(&:to_s)
          elsif agent.is_a?(Array) && !agent.empty?
            prompt = fields['prompt'].to_s.strip
            raise Error, "#{name}: prompt is empty" if prompt.empty?

            [*agent.map(&:to_s), prompt]
          else
            raise Error, "#{name}: a prompt loop needs an explicit agent: argv (e.g. [claude, -p]) or a command: argv"
          end
        end
        bypass = argv.grep(BYPASS)
        raise Error, "#{name}: permission-bypass flags are not allowed in recurring recipes (#{bypass.join(', ')})" unless bypass.empty?

        [resolve_executable(name, argv.first, env), *argv.drop(1)]
      end

      def resolve_executable(name, executable, env)
        return File.expand_path(executable) if executable.include?('/')

        path = env.fetch('PATH', ENV.fetch('PATH', ''))
        found = path.split(':').map { |dir| File.join(dir, executable) }.find { |file| File.file?(file) && File.executable?(file) }
        found || raise(Error, "#{name}: #{executable} not found on PATH")
      end

      # One occurrence, if due. scheduled: true is launchd's invocation, which
      # does nothing unless the schedule is enabled.
      #   => { status: :disabled | :not_due | :missed | :ran, occurrence:, outcome: JobOutcome | nil }
      def tick(definition, now: Time.now, scheduled: false)
        checkpoint = ScheduleCheckpoint.for(definition.name)
        return { status: :disabled } if scheduled && !checkpoint&.enabled

        occurrence = definition.due(now)
        return { status: :not_due, occurrence: occurrence } if checkpoint&.last_due == occurrence.key

        late = (now - occurrence.at).to_i
        if late > definition.grace && definition.missed == 'skip'
          ScheduleCheckpoint.write!(definition.name, last_due: occurrence.key, last_due_at: occurrence.at.utc.iso8601,
            detail: "skipped: #{late}s late (grace #{definition.grace}s)")
          return { status: :missed, occurrence: occurrence }
        end

        context = { 'trigger' => scheduled ? 'launchd' : 'manual', 'job' => definition.job, 'late_seconds' => late }
        outcome = Job.execute(definition.name, occurrence.key, command: definition.command, timeout: definition.timeout,
          max_concurrent: definition.max_concurrent, context: context, keep_log: definition.keep_logs,
          artifacts: definition.artifacts, now: now)
        unless outcome
          # Another worker finished this occurrence; record it if that worker could not.
          ScheduleCheckpoint.write!(definition.name, last_due: occurrence.key, last_due_at: occurrence.at.utc.iso8601)
          return { status: :not_due, occurrence: occurrence }
        end

        unless outcome.outcome == 'skipped-overlap'
          ScheduleCheckpoint.write!(definition.name, last_due: occurrence.key, last_due_at: occurrence.at.utc.iso8601,
            last_run_id: outcome.run_id, last_outcome: outcome.outcome, detail: outcome.detail)
        end
        notify(definition, outcome)
        { status: :ran, occurrence: occurrence, outcome: JobOutcome.first(run_id: outcome.run_id) }
      end

      # Delivery is recorded on the outcome; a failed delivery never changes the outcome itself.
      def notify(definition, outcome)
        wanted = definition.notify == 'always' || (definition.notify == 'failures' && !%w[completed skipped-overlap].include?(outcome.outcome))
        return unless wanted

        delivered = Notification.deliver(['-t', "hiiro #{definition.name}", '-m', "#{outcome.status_text}: #{outcome.detail}"])
        outcome.update(notification: delivered ? 'delivered' : 'failed')
      end

      def enable(definition, launchd: Launchd.new)
        launchd.enable(definition)
        ScheduleCheckpoint.write!(definition.name, label: definition.label(launchd.prefix), enabled: true,
          enabled_at: Time.now.utc.iso8601)
      end

      def disable(name, launchd: Launchd.new)
        launchd.disable(name)
        ScheduleCheckpoint.write!(name, enabled: false, disabled_at: Time.now.utc.iso8601)
      end
    end

    # launchd registration for owned labels only (PREFIX.NAME). The plist is
    # written to the user's LaunchAgents directory and bootstrapped into the GUI
    # domain; nothing else in that directory or domain is read or changed.
    class Launchd
      def self.prefix = ENV.fetch('HIIRO_LAUNCHD_PREFIX', 'com.hiiro.schedule')

      attr_reader :prefix, :agents_dir

      def initialize(prefix: self.class.prefix, agents_dir: File.join(Dir.home, 'Library/LaunchAgents'),
                     runner: ->(*argv) { Open3.capture2e(*argv) })
        @prefix = prefix
        @agents_dir = agents_dir
        @runner = runner
      end

      def domain = "gui/#{Process.uid}"
      def label(name) = "#{prefix}.#{name}"
      def plist_path(name) = File.join(agents_dir, "#{label(name)}.plist")
      def log_path(name) = File.join(Dir.home, '.local/share/hiiro/schedules', "#{name}.launchd.log")

      def program(definition) = [*Schedule.hiiro_argv('bin/h-schedule'), 'run', definition.name, '--scheduled']

      def environment(definition)
        base = { 'HOME' => Dir.home, 'LANG' => ENV.fetch('LANG', 'en_US.UTF-8'),
                 'PATH' => "#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin" }
        base.merge(definition.env)
      end

      def plist(definition)
        interval = definition.interval? ? definition.every : 60
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key>
            #{string(label(definition.name))}
            <key>ProgramArguments</key>
            <array>
          #{program(definition).map { |arg| "    #{string(arg)}" }.join("\n")}
            </array>
            <key>WorkingDirectory</key>
            #{string(definition.cwd)}
            <key>EnvironmentVariables</key>
            <dict>
          #{environment(definition).sort.map { |key, value| "    <key>#{CGI.escapeHTML(key)}</key>\n    #{string(value)}" }.join("\n")}
            </dict>
            <key>StartInterval</key>
            <integer>#{interval}</integer>
            <key>RunAtLoad</key>
            <false/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            #{string(log_path(definition.name))}
            <key>StandardErrorPath</key>
            #{string(log_path(definition.name))}
          </dict>
          </plist>
        XML
      end

      # What enable would do, without doing it.
      def plan(definition)
        [
          "label:     #{label(definition.name)}",
          "plist:     #{plist_path(definition.name)}",
          "program:   #{Shellwords.join(program(definition))}",
          "runs:      #{Shellwords.join(definition.program)}",
          "cwd:       #{definition.cwd}",
          "env:       #{environment(definition).sort.map { |key, value| "#{key}=#{value}" }.join(' ')}",
          "recurs:    #{definition.recurrence_text} (launchd wakes it every #{definition.interval? ? definition.every : 60}s)",
          "bounds:    max_concurrent #{definition.max_concurrent}, timeout #{definition.timeout}s, missed #{definition.missed}",
          "agent:     #{definition.agent ? 'yes (explicitly configured)' : 'no'}",
          "enable:    launchctl bootstrap #{domain} #{plist_path(definition.name)}",
          "disable:   launchctl bootout #{domain}/#{label(definition.name)}",
        ]
      end

      def enable(definition)
        path = plist_path(definition.name)
        FileUtils.mkdir_p([agents_dir, File.dirname(log_path(definition.name))])
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, plist(definition))
        File.rename(tmp, path)
        output, status = @runner.call('launchctl', 'bootstrap', domain, path)
        return if status.success?

        FileUtils.rm_f(path)
        raise Error, "launchctl bootstrap #{label(definition.name)} failed (exit #{status.exitstatus}): #{output.strip}; not enabled"
      end

      def disable(name)
        output, status = @runner.call('launchctl', 'bootout', "#{domain}/#{label(name)}")
        registered = !status.success? && !output.match?(/No such process|Could not find service|not find/i)
        raise Error, "launchctl bootout #{label(name)} failed (exit #{status.exitstatus}): #{output.strip}" if registered

        FileUtils.rm_f(plist_path(name))
      end

      # => { 'state' => 'not running', 'runs' => '1', 'last exit code' => '0' } or nil when not registered
      def status(name)
        output, status = @runner.call('launchctl', 'print', "#{domain}/#{label(name)}")
        return nil unless status.success?

        output.lines.each_with_object({}) do |line, fields|
          key, value = line.strip.split(' = ', 2)
          fields[key] = value if value && ['state', 'runs', 'last exit code', 'pid'].include?(key) && !fields.key?(key)
        end
      end

      private

      def string(value) = "<string>#{CGI.escapeHTML(value.to_s)}</string>"
    end

    # Loop recipes kept where h loop always stored them: ~/ai/loops/NAME/config.yml
    # ({ name, frequency, prompt } plus agent: or command:). Each is the schedule loop-NAME.
    module Loops
      module_function

      def configs
        return {} unless Dir.exist?(Schedule.loops_root)

        Dir.children(Schedule.loops_root).sort.filter_map do |name|
          path = File.join(Schedule.loops_root, name, 'config.yml')
          next unless File.file?(path)

          [name, [path, YAML.safe_load_file(path) || {}]]
        end.to_h
      end

      def fields(config)
        config = config.transform_keys(&:to_s)
        fields = { 'job' => 'loop', 'every' => config.fetch('frequency', '10m'), 'prompt' => config['prompt'] }
        %w[agent command timeout notify cwd env artifacts keep_logs].each { |key| fields[key] = config[key] if config.key?(key) }
        fields
      end
    end
  end
end
