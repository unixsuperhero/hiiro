require 'json'
require 'fileutils'
require 'securerandom'
require 'time'
require 'rbconfig'
require 'shellwords'
require_relative 'error'
require_relative 'shell'

class Hiiro
  # One launched command and what is known about it. A terminal allocation is
  # `allocated`; only the supervisor that spawned the child records `started`,
  # a configured probe records `ready`, and the observed child status records
  # `completed` (exit 0) or `failed` (nonzero exit, signal, or launch error).
  class OwnedRun
    STATES = %w[allocated started ready completed failed].freeze
    TRANSITIONS = {
      'allocated' => %w[started failed],
      'started' => %w[ready completed failed],
      'ready' => %w[completed failed],
      'completed' => [],
      'failed' => [],
    }.freeze
    ACTIVE = %w[allocated started ready].freeze

    class InvalidTransition < Hiiro::Error; end

    class LaunchError < Hiiro::Error
      attr_reader :run

      def initialize(run)
        @run = run
        super("Launch failed (#{run.id}): #{run.error}")
      end
    end

    # What a consumer asks to run. owner names who owns the run; placement says
    # where it runs; process_group isolates the child so a stop reaches its whole tree.
    LaunchRequest = Struct.new(:id, :owner, :command, :placement, :process_group, :ready, keyword_init: true) do
      def initialize(**)
        super
        self.id ||= OwnedRun.new_id
        self.owner = owner.transform_keys(&:to_s)
        self.placement = (placement || {}).transform_keys(&:to_s)
        self.process_group = !!process_group
      end
    end

    # pid plus the kernel's start time for it, so a reused pid is never mistaken for ours.
    class ProcessIdentity
      def self.of(pid)
        started = IO.popen(['ps', '-o', 'lstart=', '-p', pid.to_s], err: File::NULL, &:read).to_s.strip
        started.empty? ? nil : new(pid: pid, started: started)
      end

      def self.from_h(hash) = hash && new(pid: hash['pid'], started: hash['started'])

      attr_reader :pid, :started

      def initialize(pid:, started:)
        @pid = pid
        @started = started
      end

      def alive? = self.class.of(pid)&.started == started
      def to_h = { 'pid' => pid, 'started' => started }
    end

    def self.new_id = "run-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"

    attr_reader :data

    def initialize(data)
      @data = data
    end

    def self.allocate(request, terminal: nil)
      build(request, 'allocated', terminal: terminal)
    end

    def self.failed(request, error, terminal: nil)
      build(request, 'failed', terminal: terminal).tap { |run| run.data['error'] = error }
    end

    def self.build(request, state, terminal:)
      now = Time.now.iso8601
      new(
        'id' => request.id,
        'owner' => request.owner,
        'command' => request.command.to_h,
        'placement' => request.placement,
        'process_group' => request.process_group,
        'ready' => request.ready&.to_h,
        'state' => state,
        'terminal' => terminal&.to_meta,
        'process' => nil,
        'outcome' => nil,
        'error' => nil,
        'times' => { state => now },
      )
    end

    def id            = data['id']
    def owner         = data['owner']
    def state         = data['state']
    def placement     = data['placement'] || {}
    def error         = data['error']
    def times         = data['times'] || {}
    def process_group? = data['process_group'] == true
    def command       = CommandSpecification.from_h(data['command'])
    def ready_probe   = data['ready'] && CommandSpecification.from_h(data['ready'])
    def process       = ProcessIdentity.from_h(data['process'])
    def outcome       = ProcessOutcome.from_h(data['outcome'])
    def terminal      = data['terminal'] && Herdr::Location.from_meta(data['terminal'])

    def allocated? = state == 'allocated'
    def active?    = ACTIVE.include?(state)
    def finished?  = !active?

    def start(identity) = transition('started', 'process' => identity.to_h)
    def ready = transition('ready')
    def fail(message) = transition('failed', 'error' => message)

    def finish(outcome)
      transition(outcome.success? ? 'completed' : 'failed', 'outcome' => outcome.to_h)
    end

    def transition(to, **attrs)
      unless TRANSITIONS.fetch(state).include?(to)
        raise InvalidTransition, "#{id} cannot go from #{state} to #{to}"
      end

      data.merge!(attrs.transform_keys(&:to_s))
      data['state'] = to
      data['times'] = times.merge(to => Time.now.iso8601)
      self
    end

    # One line for listings: "started pid 4242", "failed exit 7", "failed: no tab".
    def summary
      return "#{state} #{outcome}" if outcome
      return "#{state}: #{error}" if error
      return "#{state} pid #{process.pid}" if process

      state
    end

    def to_h = data

    # Run records are runtime files: one JSON document per run, rewritten
    # atomically under a per-run lock.
    class Store
      def self.default = new(File.join(Dir.home, '.local/share/hiiro/runs'))

      attr_reader :dir

      def initialize(dir)
        @dir = dir
      end

      def path_for(id) = File.join(dir, "#{id}.json")

      def find(id)
        path = path_for(id)
        File.exist?(path) ? OwnedRun.new(JSON.parse(File.read(path))) : nil
      end

      def all
        Dir.glob(File.join(dir, 'run-*.json')).sort.map { |path| OwnedRun.new(JSON.parse(File.read(path))) }
      end

      def create(run)
        FileUtils.mkdir_p(dir)
        lock(run.id) do
          raise Hiiro::Error, "Run already exists: #{run.id}" if File.exist?(path_for(run.id))

          write(run)
        end
        run
      end

      # Reads the current record, yields it, and saves whatever the block left.
      def update(id)
        lock(id) do
          run = find(id) || raise(Hiiro::Error, "Run not found: #{id}")
          yield run
          write(run)
          run
        end
      end

      private

      def lock(id)
        FileUtils.mkdir_p(dir)
        File.open(File.join(dir, "#{id}.lock"), File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          yield
        end
      end

      def write(run)
        tmp = "#{path_for(run.id)}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(run.to_h))
        File.rename(tmp, path_for(run.id))
      end
    end

    # Owner-specific bookkeeping after a run finishes. Loaded lazily because the
    # supervisor runs without the rest of Hiiro.
    SETTLEMENTS = {
      'queue' => ['queue_claim', :QueueClaim],
      'background' => ['pane_reservations', :PaneReservations],
    }.freeze

    def self.settle(run, store:)
      feature, constant = SETTLEMENTS[run.owner['kind']]
      return unless feature && run.finished?

      require_relative feature
      Hiiro.const_get(constant).settle(run, store: store)
    end

    # Runs inside the allocated terminal (or replaces the current process):
    # spawns the child, records its identity, waits, and records the outcome.
    class Supervisor
      def self.main(argv)
        path = argv.fetch(0)
        new(Store.new(File.dirname(path)), File.basename(path, '.json')).run
      end

      def self.argv(store, id)
        [RbConfig.ruby, '-I', File.expand_path('..', __dir__), '-r', 'hiiro/owned_run',
          '-e', 'exit Hiiro::OwnedRun::Supervisor.main(ARGV)', store.path_for(id)]
      end

      def initialize(store, id)
        @store = store
        @id = id
      end

      def run
        pid = nil
        run = @store.update(@id) do |record|
          next unless record.allocated?

          spec = record.command
          begin
            pid = Process.spawn(*spec.spawn_args(pgroup: record.process_group? || nil))
            record.start(ProcessIdentity.of(pid) || ProcessIdentity.new(pid: pid, started: nil))
          rescue SystemCallError => e
            record.fail("#{spec.preview}: #{e.message}")
          end
        end

        unless pid
          warn "[#{@id}] not started: #{run.error || run.state}"
          OwnedRun.settle(run, store: @store)
          return 127
        end

        forward_signals(pid, run.process_group?)
        probe = watch_ready(run, pid)
        _, status = Process.wait2(pid)
        probe&.kill
        outcome = ProcessOutcome.from_status(status)
        run = @store.update(@id) { |record| record.finish(outcome) if record.active? }
        OwnedRun.settle(run, store: @store)
        outcome.shell_code
      end

      private

      # Interactive children share our foreground group and receive terminal
      # signals themselves; isolated groups need them forwarded.
      def forward_signals(pid, group)
        %w[INT TERM HUP QUIT].each do |signal|
          trap(signal) do
            target = group ? -pid : pid
            Process.kill(signal, target) if group || !%w[INT QUIT].include?(signal)
          rescue Errno::ESRCH
            nil
          end
        end
      end

      def watch_ready(run, pid)
        probe = run.ready_probe
        return unless probe

        Thread.new do
          loop do
            if system(*probe.spawn_args(out: File::NULL, err: File::NULL))
              @store.update(@id) { |record| record.ready if record.state == 'started' }
              break
            end
            sleep 0.2
          end
        end
      end
    end

    # Allocates a place for a request, records the run, hands it to the supervisor,
    # and returns only once the supervisor has started the child. Every failure
    # leaves a failed record and raises LaunchError.
    class Launcher
      attr_reader :store, :start_timeout

      def initialize(store: Store.default, herdr: nil, start_timeout: 10)
        @store = store
        @herdr = herdr
        @start_timeout = start_timeout
      end

      def herdr = @herdr ||= Hiiro::Herdr.client

      def supervisor_argv(id) = Supervisor.argv(store, id)

      # Replaces the current process with the supervisor; returns only on failure.
      def current(request, terminal: Herdr::Location.from_env, on_allocated: nil)
        run = allocate(request, terminal, on_allocated)
        exec(*supervisor_argv(run.id))
      rescue SystemCallError => e
        abandon(run, "exec failed: #{e.message}") if run
        raise LaunchError, store.find(request.id) if run
        raise
      end

      # With log:, the supervisor and the child it spawns write stdout and stderr there.
      def detached(request, on_allocated: nil, log: nil)
        run = allocate(request, nil, on_allocated)
        output = log ? { out: [log, 'a'], err: [:child, :out] } : {}
        pid = Process.spawn(*supervisor_argv(run.id), in: File::NULL, pgroup: true, **output)
        Process.detach(pid)
        wait_started(run)
      end

      def herdr_tab(request, workspace:, name:, focus: false, on_allocated: nil)
        created = Herdr::TabCreation.create(herdr, name: name, workspace: workspace,
          start_directory: request.command.cwd, focus: focus)
        unless created.complete?
          herdr.close_tab(created.tab_id) if created.created?
          record_failure(request, "Herdr did not create a tab (#{created.errors.join(', ')})")
        end
        deliver(request, created.location(workspace_id: workspace.respond_to?(:id) ? workspace.id : nil),
          on_allocated, close: -> { herdr.close_tab(created.tab_id) })
      end

      def herdr_split(request, target:, direction:, focus: true, on_allocated: nil)
        pane = herdr.split_pane(target: target, direction: direction, start_directory: request.command.cwd, focus: focus)
        record_failure(request, "Herdr did not split pane #{target}") unless pane&.id
        location = Herdr::Location.new(workspace_id: pane.workspace_id, tab_id: pane.tab_id, pane_id: pane.id)
        deliver(request, location, on_allocated, close: -> { herdr.close_pane(pane.id) })
      end

      # An existing pane the caller already owns (e.g. a reserved idle pane).
      def herdr_pane(request, location, on_allocated: nil)
        deliver(request, location, on_allocated, close: nil)
      end

      private

      def allocate(request, terminal, on_allocated)
        run = store.create(OwnedRun.allocate(request, terminal: terminal))
        on_allocated&.call(run)
        run
      rescue Exception => e
        abandon(run, "launch interrupted: #{e.message}") if run
        raise
      end

      def deliver(request, location, on_allocated, close:)
        run = allocate(request, location, on_allocated)
        unless herdr.run_in_pane(location.pane_id, Shellwords.join(supervisor_argv(run.id)))
          close&.call
          abandon(run, "Herdr did not run the command in pane #{location.pane_id}")
          raise LaunchError, store.find(run.id)
        end
        wait_started(run)
      end

      def wait_started(run)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + start_timeout
        loop do
          current = store.find(run.id)
          return current if current.process
          raise LaunchError, current if current.failed?
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.05
        end
        abandon(run, "start not observed within #{start_timeout}s")
        current = store.find(run.id)
        current.process ? current : raise(LaunchError, current)
      rescue Interrupt
        abandon(run, 'launch interrupted')
        raise
      end

      # Fails a run that never started; a run the supervisor already started is left alone.
      def abandon(run, message)
        updated = store.update(run.id) { |record| record.fail(message) if record.allocated? }
        OwnedRun.settle(updated, store: store)
        updated
      end

      def record_failure(request, message)
        run = store.create(OwnedRun.failed(request, message))
        OwnedRun.settle(run, store: store)
        raise LaunchError, run
      end
    end

    def failed? = state == 'failed'
  end
end
