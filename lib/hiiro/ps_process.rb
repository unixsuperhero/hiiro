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

  # Find processes with files open in given directories
  def self.in_dirs(*paths)
    pids = Set.new
    paths.each do |path|
      expanded = File.expand_path(path)
      lsof_output = `lsof +D #{expanded.shellescape} 2>/dev/null`.lines[1..]
      next unless lsof_output

      lsof_output.each do |line|
        fields = line.split
        pids << fields[1] if fields[1]
      end
    end

    all.select { |p| pids.include?(p.pid) }
  end

  # Open files for this process
  def files
    lines = `lsof -p #{pid} 2>/dev/null`.lines[1..] || []
    lines.filter_map do |line|
      parts = line.split
      { fd: parts[3], type: parts[4], name: parts[8] } if parts.size >= 9
    end
  end

  # Open network ports for this process
  def ports
    lines = `lsof -a -p #{pid} -i 2>/dev/null`.lines[1..] || []
    lines.filter_map do |line|
      parts = line.split
      { protocol: parts[7], name: parts[8] } if parts.size >= 9
    end
  end

  # Current working directory
  def dir
    cwd_line = `lsof -p #{pid} 2>/dev/null | grep ' cwd '`.strip
    return nil if cwd_line.empty?
    cwd_line.split.last
  end

  # Parent process
  def parent
    ppid = `ps -o ppid= -p #{pid}`.strip
    return nil if ppid.empty?
    self.class.find(ppid)
  end

  # Child processes
  def children
    child_pids = `pgrep -P #{pid}`.lines.map(&:strip)
    child_pids.filter_map { |cpid| self.class.find(cpid) }
  end

  # Simple display: PID and CMD
  def to_s
    "#{pid}\t#{cmd}"
  end

  # Detailed display
  def inspect
    "#<PsProcess pid=#{pid} user=#{user} stat=#{stat} cmd=#{cmd.slice(0, 40)}...>"
  end
end
