require 'test_helper'
require 'open3'
require 'rbconfig'
require 'socket'
require 'json'
require 'pty'

# Select, open, and copy across bookmarks, Obsidian notes, and Portfolio
# documents, run as real processes. Several matches open the shared picker on
# a pseudo-terminal, driven by keys; `open` and `pbcopy` on PATH are recorders.
class SavedSelectionTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  FIXTURES = {
    'pbcopy' => <<~'SH',
      #!/bin/sh
      cat > "$COPY_LOG"
    SH
    'pbpaste' => "#!/bin/sh\nexit 0\n",
    'open' => <<~'SH',
      #!/bin/sh
      printf '%s\n' "$*" >> "$OPEN_LOG"
    SH
    'editor' => <<~'SH'
      #!/bin/sh
      if [ -n "$EDIT_CONTENT_FILE" ]; then cat "$EDIT_CONTENT_FILE" > "$1"; fi
      exit 0
    SH
  }.freeze

  def setup
    @root = File.realpath(Dir.mktmpdir('saved-selection-'))
    @home = File.join(@root, 'home')
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([@home, @bin])
    FIXTURES.each do |name, body|
      File.write(File.join(@bin, name), body)
      File.chmod(0o755, File.join(@bin, name))
    end
    @db_path = File.join(@root, 'hiiro.db')
    _, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', 'require "hiiro"; Hiiro::DB.setup!', unsetenv_others: true)
    assert status.success?, err
    @db = Sequel.sqlite(@db_path)
  end

  def teardown
    @db&.disconnect
    @server&.close
    @server_thread&.kill
    FileUtils.remove_entry(@root)
  end

  def log(name) = File.join(@root, "#{name}.log")
  def lines(name) = File.exist?(log(name)) ? File.readlines(log(name), chomp: true) : []

  def env(**extra)
    { 'HOME' => @home, 'USER' => 'tester', 'PATH' => "#{@bin}:#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'HIIRO_TEST_DB' => "sqlite://#{@db_path}", 'EDITOR' => File.join(@bin, 'editor'), 'TERM' => 'dumb',
      'OPEN_LOG' => log('open'), 'COPY_LOG' => log('copy'), 'LINES' => '8', 'COLUMNS' => '70' }.merge(extra.transform_keys(&:to_s))
  end

  def h(bin, *args, **extra)
    out, err, status = Open3.capture3(env(**extra), RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', "h-#{bin}"), *args,
                                      chdir: @root, unsetenv_others: true)
    [out, err, status.exitstatus]
  end

  # Runs the command on a pseudo-terminal. With keys, waits for the picker to
  # draw, types them, and returns [output after the picker closed, exit
  # status, the last picker frame as plain rows]; without keys, [output,
  # status, nil].
  def h_tty(bin, *args, keys: nil, **extra) = run_tty([File.join(ROOT, 'bin', "h-#{bin}"), *args], keys: keys, **extra)

  def run_tty(argv, keys: nil, **extra)
    output = +''
    status = nil
    PTY.spawn(env(**extra), RbConfig.ruby, '-I', File.join(ROOT, 'lib'), *argv, chdir: @root, unsetenv_others: true) do |reader, writer, pid|
      if keys
        deadline = Time.now + 15
        until output.include?('Enter choose')
          flunk "picker never drew:\n#{output}" if Time.now > deadline
          output << reader.readpartial(4096) if IO.select([reader], nil, nil, 0.2)
        end
        writer.write(keys)
      end
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      status = Process.wait2(pid).last
    end
    return [output.gsub("\r\n", "\n"), status.exitstatus, nil] unless keys

    screen, _, after = output.rpartition("\e[?1049l")
    frame = screen.split("\e[H\e[2J").last.to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, '').split("\r\n").map(&:rstrip)
    [after.gsub("\r\n", "\n"), status.exitstatus, frame]
  end

  def test_equal_labels_resolve_to_the_chosen_original_record
    script = <<~'RUBY'
      require 'hiiro'
      items = [1, 2, 3].map { |n| Hiiro::Selection::Item.new(id: "rec:#{n}", title: 'Same title', record: n) }
      p Hiiro::Selection.pick(items, picker: 'same', tty: true)&.record
    RUBY
    out, status, frame = run_tty(['-e', script], keys: "j\r")
    assert_equal ["2\n", 0], [out, status]
    assert_equal ['same  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded', '   Same title', '>  Same title', '   Same title', '', '', '2/3'], frame

    out, status, = run_tty(['-e', script], keys: 'q')
    assert_equal ["nil\n", 0], [out, status]
  end

  def test_bookmarks_open_copy_and_select_the_picked_link_with_its_template_filled
    @db[:registry].insert(id: 10, resource_type: 'link', name: 'Docs', value: 'https://example.com/a', description: 'Docs', created_at: '2026-01-01T00:00:00Z')
    @db[:registry].insert(id: 11, resource_type: 'link', name: 'https://example.com/{org}/{repo}', value: 'https://example.com/{org}/{repo}', description: 'Docs', created_at: '2026-01-02T00:00:00Z')
    @db[:registry].insert(id: 12, resource_type: 'link', name: 'Other', value: 'https://other.test', description: 'Other', created_at: '2026-01-03T00:00:00Z')
    values = File.join(@root, 'values.yml')
    File.write(values, "org: a b\nrepo: r\n")

    out, status, frame = h_tty('link', 'open', 'docs', keys: "j\r", EDIT_CONTENT_FILE: values)
    assert_equal ['', 0], [out, status]
    assert_equal ['https://example.com/a+b/r'], lines('open')
    assert_equal ['links  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded', '   1. https://example.com/a - Docs',
                  '>  2. https://example.com/{org}/{repo} - Docs', '', '', '', '2/2'], frame

    out, status, = h_tty('link', 'copy', 'docs', keys: "\r")
    assert_equal ["Copied URL 'https://example.com/a' to clipboard\n", 0], [out, status]
    assert_equal 'https://example.com/a', File.read(log('copy'))

    out, status, = h_tty('link', 'select', keys: "/other\r\r")
    assert_equal ["https://other.test\n", 0], [out, status]

    FileUtils.rm_f(log('open'))
    out, status, = h_tty('link', 'open', 'docs', keys: 'q')
    assert_equal ["No link selected.\n", 1], [out, status]
    out, err, status = h('link', 'open', 'zzz')
    assert_equal ['', "Link not found: zzz\n", 1], [out, err, status]
    out, err, status = h('link', 'open', '2')
    assert_equal ['', "Cancelled.\n", 1], [out, err, status]
    File.write(values, "org: [unclosed\n")
    out, err, status = h('link', 'open', '2', EDIT_CONTENT_FILE: values)
    assert_equal ['', 1], [out, status]
    kept = err[/edited text kept at (\S+)$/, 1]
    assert_match(%r{\A\(\S+link-params-\S+\.yml\): did not find expected ',' or '\]' while parsing a flow sequence at line 1 column 6; edited text kept at #{Regexp.escape(@home)}/\.local/share/hiiro/edits/link-params-\d{14}-\h{6}\.yml\n\z}, err)
    assert_equal "org: [unclosed\n", File.read(kept)
    assert_empty lines('open')
    assert_equal [10, 11, 12], @db[:registry].where(resource_type: 'link').order(:id).select_map(:id)
  end

  def obsidian_vault
    vault = File.join(@root, 'Work Vault')
    { 'tasks/plan.md' => "# Plan\n", 'refs/plan.md' => "# Plan\n", 'refs/other.md' => "# Other\n" }.each do |rel, body|
      FileUtils.mkdir_p(File.join(vault, 'cld', File.dirname(rel)))
      File.write(File.join(vault, 'cld', rel), body)
    end
    FileUtils.mkdir_p(File.join(@home, '.config/hiiro'))
    File.write(File.join(@home, '.config/hiiro/config.yml'), { 'obsidian' => { 'vault_name' => 'Work Vault', 'vault_dir' => vault } }.to_yaml)
  end

  def test_obsidian_keeps_vault_uris_exact_refs_and_ambiguity_rules
    obsidian_vault
    out, err, status = h('obsidian', 'open', 'refs/plan.md')
    assert_equal ['', '', 0], [out, err, status]
    assert_equal ['obsidian://open?vault=Work+Vault&file=cld%2Frefs%2Fplan'], lines('open')

    out, err, status = h('obsidian', 'copy', 'Plan')
    assert_equal ['', 1], [out, status]
    assert_equal "Multiple notes matched:\n  1. Plan [cld/tasks/plan.md]\n  2. Plan [cld/refs/plan.md]\n", err

    output, status, = h_tty('obsidian', 'copy', 'Plan', keys: "j\r")
    assert_equal ["Copied obsidian://open?vault=Work+Vault&file=cld%2Frefs%2Fplan\n", 0], [output, status]
    assert_equal 'obsidian://open?vault=Work+Vault&file=cld%2Frefs%2Fplan', File.read(log('copy'))
    output, status, = h_tty('obsidian', 'open', 'Plan', keys: 'q')
    assert_equal ["No note selected.\n", 1], [output, status]
    assert_equal 1, lines('open').length
  end

  def portfolio(items)
    @requests = Queue.new
    @server = TCPServer.new('127.0.0.1', 0)
    @server_thread = Thread.new do
      Thread.current.report_on_exception = false
      loop do
        client = @server.accept
        request = client.gets
        nil until client.gets == "\r\n"
        @requests << request.split[1]
        body = JSON.generate('items' => items)
        client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    end
    "http://127.0.0.1:#{@server.addr[1]}"
  end

  def test_portfolio_opens_and_copies_by_api_identity
    base = portfolio([
      { 'id' => 41, 'title' => 'Plan', 'type' => 'doc', 'href' => '/d/41', 'source_path' => '/notes/a.md' },
      { 'id' => 42, 'title' => 'Plan', 'type' => 'doc', 'href' => '/d/42', 'source_path' => '/notes/b.md' },
      { 'id' => 43, 'title' => 'Ext', 'type' => 'link', 'href' => 'https://ext.test/x', 'source_path' => nil }
    ])
    out, status, = h_tty('docs', 'open', 'plan', keys: "j\r", HDOCS_SERVER: base)
    assert_equal ['', 0], [out, status]
    assert_equal ["#{base}/d/42"], lines('open')
    assert_equal '/api/items?q=plan', @requests.pop

    out, status, = h_tty('docs', 'copy', 'plan', keys: "\r", HDOCS_SERVER: base)
    assert_equal ["#{base}/d/41\n", 0], [out, status]
    assert_equal "#{base}/d/41", File.read(log('copy'))

    out, _, status = h('docs', 'url', '--all', 'plan', HDOCS_SERVER: base)
    assert_equal ["#{base}/d/41\n#{base}/d/42\nhttps://ext.test/x\n", 0], [out, status]
    out, _, status = h('docs', 'open', '--all', 'plan', HDOCS_SERVER: base)
    assert_equal 0, status
    assert_equal ["#{base}/d/42", "#{base}/d/41", "#{base}/d/42", 'https://ext.test/x'], lines('open')

    out, status, = h_tty('docs', 'open', 'plan', keys: 'q', HDOCS_SERVER: base)
    assert_equal 1, status
    assert_equal 4, lines('open').length
  end
end
