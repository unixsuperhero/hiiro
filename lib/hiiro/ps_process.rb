require 'set'
require 'shellwords'

class Hiiro::PsProcess
  attr_reader :user, :pid, :cpu, :mem, :vsz, :rss, :tty, :stat, :start, :time, :cmd

  def initialize(user:, pid:, cpu:, mem:, vsz:, rss:, tty:, stat:, start:, time:, cmd:)
    @user = user
    @pid = pid
    @cpu = cpu
    @mem = mem
    @vsz = vsz
    @rss = rss
    @tty = tty
    @stat = stat
    @start = start
    @time = time
    @cmd = cmd
  end

  # Parse a line from `ps awwux` output
  # Format: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND...
  def self.from_line(line)
    parts = line.split
    return nil if parts.size < 11

    new(
      user: parts[0],
      pid: parts[1],
      cpu: parts[2],
      mem: parts[3],
      vsz: parts[4],
      rss: parts[5],
      tty: parts[6],
      stat: parts[7],
      start: parts[8],
      time: parts[9],
      cmd: parts[10..].join(' ')
    )
  end

  # One `ps awwux` capture; every question below reads the same table.
  class Snapshot
    def self.capture
      new(Hiiro::PsProcess.all, captured_at: Time.now)
    end

    attr_reader :processes, :captured_at

    def initialize(processes, captured_at: Time.now)
      @processes = processes
      @captured_at = captured_at
    end

    def by_pid(pid)          = processes.find { |p| p.pid == pid.to_s }
    def with_pids(pids)      = processes.select { |p| pids.include?(p.pid) }
    def matching(pattern)    = processes.select { |p| p.cmd.include?(pattern) || p.user.include?(pattern) }

    def parent_of(pid)
      ppid = `ps -o ppid= -p #{pid.to_i}`.strip
      return nil if ppid.empty?
      by_pid(ppid)
    end

    def children_of(pid)
      `pgrep -P #{pid.to_i}`.lines.map(&:strip).filter_map { |cpid| by_pid(cpid) }
    end
  end

  # One lsof invocation, parsed once. `failed` is true when lsof exited
  # non-zero, which is distinct from an empty result.
  class OpenFiles
    def self.for_pid(pid, network_only: false)
      args = network_only ? ['-a', '-p', pid.to_s, '-i'] : ['-p', pid.to_s]
      run(args)
    end

    def self.for_port(port) = run(['-i', ":#{port.to_i}"])
    def self.in_dir(path)   = run(['+D', File.expand_path(path)])

    def self.run(args)
      raw = `lsof #{args.shelljoin} 2>/dev/null`
      new(args, raw, failed: !$?.success?)
    end

    attr_reader :query, :raw, :rows, :failed

    def initialize(query, raw, failed: false)
      @query = query
      @raw = raw
      @failed = failed
      @rows = raw.lines[1..].to_a.map(&:split)
    end

    def pids = rows.filter_map { |r| r[1] }.to_set

    # { fd:, type:, name: } per row, as PsProcess#files has always returned
    def files = rows.filter_map { |r| { fd: r[3], type: r[4], name: r[8] } if r.size >= 9 }

    # { protocol:, name: } per row, as PsProcess#ports has always returned
    def sockets = rows.filter_map { |r| { protocol: r[7], name: r[8] } if r.size >= 9 }

    def cwd
      row = rows.find { |r| r[3] == 'cwd' }
      row&.last
    end
  end

  # Get all processes
  def self.all
    `ps awwux`.lines[1..].filter_map { |line| from_line(line) }
  end

  # Search processes by pattern (matches against full line)
  def self.search(pattern)
    all.select { |p| p.cmd.include?(pattern) || p.user.include?(pattern) }
  end

  # Find process by PID
  def self.find(pid)
    all.find { |p| p.pid == pid.to_s }
  end

  # Find processes listening on given port numbers
  def self.by_port(*ports)
    pids = ports.flat_map { |port| OpenFiles.for_port(port).pids.to_a }.to_set
    Snapshot.capture.with_pids(pids)
  end

  # Find processes with files open in given directories
  def self.in_dirs(*paths)
    pids = paths.flat_map { |path| OpenFiles.in_dir(path).pids.to_a }.to_set
    Snapshot.capture.with_pids(pids)
  end

  # One lsof for files and cwd.
  def open_files
    @open_files ||= OpenFiles.for_pid(pid)
  end

  # Open files for this process: [{ fd:, type:, name: }]
  def files = open_files.files

  # Open network ports for this process: [{ protocol:, name: }]
  def ports = OpenFiles.for_pid(pid, network_only: true).sockets

  # Current working directory
  def dir = open_files.cwd

  # Parent process
  def parent = Snapshot.capture.parent_of(pid)

  # Child processes
  def children = Snapshot.capture.children_of(pid)

  # Simple display: PID and CMD
  def to_s
    "#{pid}\t#{cmd}"
  end

  # Detailed display
  def inspect
    "#<PsProcess pid=#{pid} user=#{user} stat=#{stat} cmd=#{cmd.slice(0, 40)}...>"
  end
end
