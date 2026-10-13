require 'open3'
require 'rbconfig'
require 'pty'
require 'fileutils'
require 'tmpdir'

# Runs real bins in a throwaway HOME with a file database and fixture tools
# that log their argv and working directory. `pick` drives the picker on a
# pseudo-terminal (the pattern of picker_consumers_test.rb).
module CliSandbox
  ROOT = File.expand_path('../..', __dir__)

  def setup_sandbox
    @root = File.realpath(Dir.mktmpdir('cli-sandbox-'))
    @home = File.join(@root, 'home')
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([@home, @bin])
    @db_path = File.join(@root, 'hiiro.db')
  end

  def teardown_sandbox
    FileUtils.remove_entry(@root) if @root
  end

  # A fixture command that appends "ARGV | cwd=DIR" to ROOT/NAME.log; body
  # (shell) runs after logging.
  def recorder(name, body = '')
    path = File.join(@bin, name)
    File.write(path, %(#!/bin/sh\nprintf '%s | cwd=%s\\n' "$*" "$(pwd)" >> "#{@root}/#{name}.log"\n#{body}))
    File.chmod(0o755, path)
  end

  def log(name)
    path = File.join(@root, "#{name}.log")
    File.exist?(path) ? File.read(path) : ''
  end

  def sandbox_env(extra = {})
    { 'HOME' => @home, 'PATH' => "#{@bin}:#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'HIIRO_TEST_DB' => "sqlite://#{@db_path}", 'TERM' => 'dumb', 'EDITOR' => File.join(@bin, 'editor'),
      'LINES' => '9', 'COLUMNS' => '120' }.merge(extra)
  end

  def bin_argv(bin, *args) = [RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', bin), *args]

  # [stdout, stderr, exit status], stdin not a terminal.
  def run_bin(bin, *args, chdir: @home, env: {}, stdin: '')
    out, err, status = Open3.capture3(sandbox_env(env), *bin_argv(bin, *args), chdir: chdir, unsetenv_others: true, stdin_data: stdin)
    [out, err, status.exitstatus]
  end

  def ruby_in_sandbox(code, chdir: @home)
    out, err, status = Open3.capture3(sandbox_env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', "require 'hiiro'\n#{code}",
                                      chdir: chdir, unsetenv_others: true)
    raise "ruby failed: #{err}" unless status.success?

    out
  end

  # [output after the picker closed, exit status, last frame as plain rows]
  def pick(bin, args, keys, chdir: @home, env: {})
    output = +''
    status = nil
    PTY.spawn(sandbox_env(env), *bin_argv(bin, *args), chdir: chdir, unsetenv_others: true) do |reader, writer, pid|
      begin
        deadline = Time.now + 15
        until output.include?('Enter choose')
          raise "picker never drew:\n#{output}" if Time.now > deadline

          output << reader.readpartial(4096) if IO.select([reader], nil, nil, 0.2)
        end
        writer.write(keys)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
        end
        status = Process.wait2(pid).last
      ensure
        unless status
          Process.kill('KILL', pid) rescue nil
          Process.wait(pid) rescue nil
        end
      end
    end
    screen, _, after = output.rpartition("\e[?1049l")
    frame = screen.split("\e[H\e[2J").last.to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, '').split("\r\n").map(&:rstrip)
    [after.gsub("\r\n", "\n"), status.exitstatus, frame]
  end
end

# A disposable repository whose commits have fixed authors and dates, so
# their SHAs are the same on every run.
module CommitFixture
  GIT_ENV = { 'GIT_AUTHOR_NAME' => 't', 'GIT_AUTHOR_EMAIL' => 't@t', 'GIT_COMMITTER_NAME' => 't',
              'GIT_COMMITTER_EMAIL' => 't@t', 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' }.freeze

  def git_in(repo, *args)
    out, err, status = Open3.capture3(GIT_ENV, 'git', '-C', repo, *args)
    raise "git #{args.join(' ')}: #{err}" unless status.success?

    out
  end

  # one (a.txt), two (b.txt, tag v1), "fix | pipes: and colons" (a.txt) on main.
  def commit_repo(repo)
    FileUtils.mkdir_p(repo)
    git_in(repo, 'init', '-q', '-b', 'main')
    [['one', 'a.txt'], ['two', 'b.txt'], ['fix | pipes: and colons', 'a.txt']].each_with_index do |(subject, file), index|
      File.write(File.join(repo, file), "#{subject}\n", mode: 'a')
      git_in(repo, 'add', file)
      date = "2026-01-0#{index + 1}T00:00:00Z"
      Open3.capture3(GIT_ENV.merge('GIT_AUTHOR_DATE' => date, 'GIT_COMMITTER_DATE' => date), 'git', '-C', repo, 'commit', '-q', '-m', subject)
      git_in(repo, 'tag', 'v1') if subject == 'two'
    end
    git_in(repo, 'rev-list', 'HEAD').split.reverse
  end
end
