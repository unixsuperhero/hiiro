require "test_helper"
require "open3"
require "pty"
require "rbconfig"
require "tmpdir"
require "json"
require "io/console"

class AsciinemaTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DEADLINE = 30
  ASCIINEMA_DIR =%w[/opt/homebrew/bin /usr/local/bin].find { |d| File.executable?(File.join(d, "asciinema")) }

  def setup
    @home = Dir.mktmpdir("cast-home")
    @casts = File.join(@home, "casts-out")
    FileUtils.mkdir_p(File.join(@home, ".config/hiiro"))
    File.write(File.join(@home, ".config/hiiro/profile.yml"), <<~YML)
      casts:
        dir: #{@casts}
        editor: [/bin/sh, -c, 'sleep 0.3; echo hello-from-cast "$@"', sh]
        resume_args: [resumed-mark]
    YML
    @today = Date.today.strftime("%Y%m%d")
  end

  def teardown = FileUtils.rm_rf(@home)

  def env
    { "HOME" => @home, "RUBYLIB" => File.join(ROOT, "lib"), "HIIRO_TEST_DB" => "sqlite::memory:",
      "PATH" => [ASCIINEMA_DIR, "/usr/bin", "/bin"].compact.join(":"), "TERM" => "xterm-256color",
      "EDITOR" => "/usr/bin/true", "VISUAL" => "/usr/bin/true" }
  end

  def h(*args)
    Open3.popen3(env, RbConfig.ruby, File.join(ROOT, "bin/h-asciinema"), *args, unsetenv_others: true, pgroup: true) do |stdin, out, err, thread|
      stdin.close
      readers = [Thread.new { out.read }, Thread.new { err.read }]
      unless thread.join(DEADLINE)
        Process.kill("KILL", -thread.pid) rescue nil
        flunk "h asciinema #{args.join(' ')} still running after #{DEADLINE}s"
      end
      [readers[0].value, readers[1].value, thread.value]
    end
  end

  def cast(index) = File.join(@casts, format("%s%03d.cast", @today, index))

  def test_names_come_from_the_profile_dir
    out, err, status = h("nname")
    assert status.success?, err
    assert_equal "#{cast(0)}\n", out
    FileUtils.mkdir_p(@casts)
    File.write(cast(0), "")
    File.write(cast(1), "")
    assert_equal "#{cast(2)}\n", h("nname")[0]
    assert_equal "#{cast(1)}\n", h("cname")[0]
    assert_equal "#{cast(0)}\n", h("pname")[0]
    assert_equal "#{cast(0)}\n#{cast(1)}\n#{cast(2)}\n", h("name", "0", "0", "2")[0]
    assert_equal "#{File.join(@casts, '20250102003.cast')}\n", h("name", "20250102", "3")[0]
    _, err, status = h("name", "0", "2", "1")
    refute status.success?
    assert_equal "ERROR: LAST_INDEX must be greater than or equal to INDEX\n", err
    _, err, = h("name")
    assert_equal "ERROR: usage: h asciinema name DAY [INDEX [LAST_INDEX]]\n", err
  end

  # asciinema rec needs a terminal; run the CLI on a PTY. The fixture editor
  # waits before printing because asciinema 3.2.1 play can drop output
  # recorded in the first ~15ms. asciinema queries the terminal and ends
  # with Primary Device Attributes (ESC [ c); with no emulator to answer,
  # it can wait forever, so answer that one query like a VT220 would.
  def on_pty(*args)
    output = +""
    status = nil
    PTY.spawn(env, RbConfig.ruby, File.join(ROOT, "bin/h-asciinema"), *args, unsetenv_others: true) do |reader, writer, pid|
      reader.winsize = [24, 80]
      answered = 0
      deadline = Time.now + DEADLINE
      begin
        loop do
          if Time.now > deadline
            Process.kill("KILL", -pid) rescue nil
            Process.wait(pid) rescue nil
            flunk "h asciinema #{args.join(' ')} still running after #{DEADLINE}s:\n#{output}"
          end
          output << reader.readpartial(4096) if IO.select([reader], nil, nil, 0.2)
          while output.scan("\e[c").size > answered
            writer.write("\e[?62;22c")
            answered += 1
          end
        end
      rescue Errno::EIO, EOFError
        nil
      end
      status = Process.wait2(pid).last
    end
    [output, status]
  end

  def events(path)
    header, *rest = File.readlines(path)
    [JSON.parse(header), rest.map { |line| JSON.parse(line) }]
  end

  def test_record_resume_and_play_through_asciinema
    skip "asciinema not installed" unless ASCIINEMA_DIR
    _, status = on_pty("record", "notes.md")
    assert status.success?
    header, evs = events(cast(0))
    assert_equal 3, header["version"]
    assert_equal %q{/bin/sh -c sleep\ 0.3\;\ echo\ hello-from-cast\ \"\$@\" sh notes.md}, header["command"]
    assert_equal "hello-from-cast notes.md\r\n", evs.find { |e| e[1] == "o" }[2]
    first = File.binread(cast(0))

    _, status = on_pty("resume", "notes.md")
    assert status.success?
    header, evs = events(cast(1))
    assert_equal %q{/bin/sh -c sleep\ 0.3\;\ echo\ hello-from-cast\ \"\$@\" sh resumed-mark notes.md}, header["command"]
    assert_equal "hello-from-cast resumed-mark notes.md\r\n", evs.find { |e| e[1] == "o" }[2]
    assert_equal first, File.binread(cast(0))

    # asciinema 3.2.1 play on a PTY sometimes prints its banners but not the
    # recorded event (about half the runs here, before and after step 15, with
    # an intact cast), so up to three plays may show it.
    outputs = []
    3.times do
      output, status = on_pty("play")
      assert status.success?
      assert_includes output, "::: Replaying session from #{cast(1)}"
      outputs << output
      break if output.include?("hello-from-cast resumed-mark notes.md")
    end
    assert_includes outputs.last, "hello-from-cast resumed-mark notes.md", File.read(cast(1))
  end
end
