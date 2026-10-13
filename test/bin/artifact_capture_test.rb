require 'test_helper'
require 'open3'
require 'rbconfig'
require 'date'
require 'base64'

# Actual h save / h img / h context / h note processes against controlled
# clipboard executables. The fixture directory comes first on PATH and holds
# every clipboard tool and opener, so the real ones are never reached.
class ArtifactCaptureTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  PNG = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\xff\x00tail".b
  TEXT = "Meeting: Notes\r\nline two \xE2\x9C\x93\n\x00raw".b

  FIXTURES = {
    'pbpaste' => <<~'SH',
      #!/bin/sh
      echo pbpaste >> "$CLIP_LOG"
      if [ -n "$CLIP_TEXT_FAIL" ]; then echo "pbpaste: pasteboard unavailable" >&2; exit 3; fi
      if [ -f "$CLIP_TEXT" ]; then cat "$CLIP_TEXT"; fi
      exit 0
    SH
    'pbcopy' => <<~'SH',
      #!/bin/sh
      cat > "$COPY_LOG"
    SH
    'open' => <<~'SH',
      #!/bin/sh
      printf '%s\n' "$*" >> "$OPEN_LOG"
    SH
    'editor' => <<~'SH',
      #!/bin/sh
      cp "$1" "$EDIT_SEEN"
      if [ -n "$EDIT_CONTENT_FILE" ]; then cat "$EDIT_CONTENT_FILE" > "$1"; fi
      exit ${EDIT_EXIT:-0}
    SH
  }.freeze

  PNGPASTE = <<~'SH'.freeze
    #!/bin/sh
    echo "pngpaste" >> "$CLIP_LOG"
    if [ -n "$CLIP_IMAGE_FAIL" ]; then echo "pngpaste: could not read pasteboard" >&2; exit 2; fi
    if [ -f "$CLIP_IMAGE" ]; then cat "$CLIP_IMAGE" > "$1"; exit 0; fi
    echo "No PNG data found on the clipboard!" >&2
    exit 1
  SH

  def setup
    @root = File.realpath(Dir.mktmpdir('artifact-capture-'))
    @home = File.join(@root, 'home')
    @bin = File.join(@root, 'bin')
    @img = File.join(@root, 'img')
    @saved = File.join(@root, 'saved')
    @ctx = File.join(@root, 'ctx')
    @notes = File.join(@root, 'notes')
    FileUtils.mkdir_p([@home, @bin, @img])
    FIXTURES.each { |name, body| fixture(@bin, name, body) }
    fixture(@img, 'pngpaste', PNGPASTE)
    @db_path = File.join(@root, 'hiiro.db')
    _, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', 'require "hiiro"; Hiiro::DB.setup!', unsetenv_others: true)
    assert status.success?, err
    @db = Sequel.sqlite(@db_path)
    @db[:tasks].insert(id: 7, name: 'alpha', status: 'waiting', next_action: 'review')
    @db[:tasks].insert(id: 8, name: 'alpine', status: 'active')
  end

  def teardown
    @db&.disconnect
    FileUtils.chmod_R('u+w', @root)
    FileUtils.remove_entry(@root)
  end

  def fixture(dir, name, body)
    path = File.join(dir, name)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def log(name) = File.join(@root, "#{name}.log")

  def env(image_tool: true, **extra)
    path = [@bin, (@img if image_tool), File.dirname(RbConfig.ruby), '/usr/bin', '/bin'].compact.join(':')
    { 'HOME' => @home, 'PATH' => path, 'LANG' => 'en_US.UTF-8', 'HIIRO_TEST_DB' => "sqlite://#{@db_path}",
      'HIIRO_SAVED_DIR' => @saved, 'H_CONTEXT_DIR' => @ctx, 'NOTES_DIR' => @notes, 'EDITOR' => File.join(@bin, 'editor'),
      'CLIP_LOG' => log('clip'), 'COPY_LOG' => log('copy'), 'OPEN_LOG' => log('open'), 'EDIT_SEEN' => File.join(@root, 'edit-seen'),
      'CLIP_TEXT' => File.join(@root, 'clip.txt'), 'CLIP_IMAGE' => File.join(@root, 'clip.png') }
      .merge(extra.transform_keys(&:to_s))
  end

  def h(bin, *args, image_tool: true, **extra)
    out, err, status = Open3.capture3(env(image_tool: image_tool, **extra), RbConfig.ruby, '-I', File.join(ROOT, 'lib'),
                                      File.join(ROOT, 'bin', "h-#{bin}"), *args, chdir: @root, unsetenv_others: true, binmode: true)
    [out.force_encoding('UTF-8'), err.force_encoding('UTF-8'), status.exitstatus]
  end

  def clipboard(text: nil, image: nil)
    text ? File.binwrite(File.join(@root, 'clip.txt'), text) : FileUtils.rm_f(File.join(@root, 'clip.txt'))
    image ? File.binwrite(File.join(@root, 'clip.png'), image) : FileUtils.rm_f(File.join(@root, 'clip.png'))
    FileUtils.rm_f(log('clip'))
  end

  def clip_calls = File.exist?(log('clip')) ? File.readlines(log('clip'), chomp: true) : []
  def saved_names = Dir.exist?(@saved) ? Dir.children(@saved).sort : []
  def bundle_path = File.join(@ctx, 'bundles', 'current.bundle')
  def task_rows(id = 7) = @db[:task_resources].where(task_id: id).order(:id).select_map(%i[kind target label])
  def task_state(id = 7) = @db[:tasks].where(id: id).select_map(%i[status next_action completed_at updated_at]).first

  def test_inbox_saves_image_first_with_exact_bytes_and_attaches_once_per_destination
    clipboard(text: TEXT, image: PNG)
    before = task_state
    out, err, status = h('save', '--bundle', '--task', 'alpha', '--label', 'shot')
    assert_equal 0, status, err
    path = out.chomp
    assert_match(%r{\A#{Regexp.escape(@saved)}/\d{14}-image\.png\z}, path)
    assert_equal PNG, File.binread(path)
    assert_equal ['pngpaste'], clip_calls
    assert_equal "attached to bundle #{bundle_path}\nattached to task alpha\n", err

    out2, err2, status2 = h('save', '--bundle', '--task', 'alpha')
    assert_equal 0, status2, err2
    second = out2.chomp
    assert_match(/-image(-2)?\.png\z/, second)
    refute_equal path, second

    _, err3, status3 = h('context', 'add', path)
    assert_equal 0, status3, err3
    out4, err4, = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e',
                                 "require 'hiiro'; Hiiro::DB.setup!; t = Hiiro::TaskRecord[7]; " \
                                 "p Hiiro::Artifact.attach_to_task(t, #{path.inspect}).created", unsetenv_others: true)
    assert_equal ["false\n", ''], [out4, err4]
    assert_equal [path, second], File.readlines(bundle_path, chomp: true)
    assert_equal [['file', path, 'shot'], ['file', second, nil]], task_rows
    assert_equal before, task_state
    assert_empty task_rows(8)
  end

  def test_inbox_text_keeps_bytes_and_never_replaces_a_file
    clipboard(text: TEXT)
    first, err, status = h('save')
    assert_equal 0, status, err
    second, err, status = h('save')
    assert_equal 0, status, err
    assert_equal ['pngpaste', 'pbpaste'], clip_calls.last(2)
    [first, second].each { |path| assert_equal TEXT, File.binread(path.chomp) }
    stamps = saved_names.map { |name| name[/\A\d{14}/] }.uniq
    expected = stamps.one? ? ["#{stamps[0]}-meeting-notes-line-two-raw-2.txt", "#{stamps[0]}-meeting-notes-line-two-raw.txt"] : saved_names
    assert_equal expected, saved_names
  end

  def test_explicit_text_argument_never_reads_the_clipboard
    clipboard(text: 'clipboard', image: PNG)
    out, err, status = h('save', 'quick', 'note')
    assert_equal 0, status, err
    assert_equal 'quick note', File.read(out.chomp)
    assert_match(/-quick-note\.txt\n\z/, out)
    assert_empty clip_calls
  end

  def test_capture_failures_are_distinct_and_write_nothing
    clipboard
    out, err, status = h('save')
    assert_equal ['', "Clipboard is empty\n", 1], [out, err, status]

    clipboard(text: 'fallback text')
    out, err, status = h('save', image_tool: false)
    assert_equal 0, status, err
    assert_equal 'fallback text', File.read(out.chomp)

    out, err, status = h('img', 'save', File.join(@root, 'shot.png'), image_tool: false)
    assert_equal ['', "pngpaste not found\n", 1], [out, err, status]
    out, err, status = h('img', 'save', File.join(@root, 'shot.png'))
    assert_equal ['', "No image in clipboard\n", 1], [out, err, status]
    refute File.exist?(File.join(@root, 'shot.png'))

    before = saved_names
    FileUtils.rm_f(log('clip'))
    out, err, status = h('save', CLIP_IMAGE_FAIL: '1')
    assert_equal ['', "pngpaste failed: pngpaste: could not read pasteboard\n", 1], [out, err, status]
    assert_equal ['pngpaste'], clip_calls
    out, err, status = h('context', 'tmp', CLIP_TEXT_FAIL: '1')
    assert_equal ['', "pbpaste failed: pbpaste: pasteboard unavailable\n", 1], [out, err, status]
    assert_equal before, saved_names

    File.write(@saved + '.file', 'not a directory')
    out, err, status = h('save', HIIRO_SAVED_DIR: @saved + '.file')
    assert_equal ['', 1], [out, status]
    assert_match(%r{\ACould not write #{Regexp.escape(@saved)}\.file/\d{14}-fallback-text\.txt: }, err)
  end

  def test_img_save_refuses_replacement_unless_forced_and_b64_reports_png
    clipboard(image: PNG)
    target = File.join(@root, 'out', 'shot.png')
    out, err, status = h('img', 'save', target)
    assert_equal ["Saved to #{target}\n", '', 0], [out, err, status]
    assert_equal PNG, File.binread(target)

    clipboard(image: PNG + 'changed'.b)
    out, err, status = h('img', 'save', target)
    assert_equal ['', "#{target} already exists (use --force to replace it)\n", 1], [out, err, status]
    assert_equal PNG, File.binread(target)
    out, _, status = h('img', 'save', '--force', target)
    assert_equal ["Saved to #{target}\n", 0], [out, status]
    assert_equal PNG + 'changed'.b, File.binread(target)

    out, _, status = h('img', 'b64')
    assert_equal ["data:image/png;base64,#{Base64.strict_encode64(PNG + 'changed'.b)}\n", 0], [out, status]
  end

  def test_context_named_capture_keeps_manifest_intent_and_reports_failed_attachment
    clipboard(text: "context text\n")
    day = File.join(@ctx, Date.today.strftime('%Y-%m-%d'))
    out, err, status = h('context', 'save', 'notes.md', '--task', 'alpha')
    assert_equal 0, status, err
    assert_equal "#{day}/notes.md\n", out
    assert_equal "context text\n", File.read(File.join(day, 'notes.md'))
    assert_equal ["#{day}/notes.md"], File.readlines(bundle_path, chomp: true)

    out, err, status = h('context', 'save', 'notes.md')
    assert_equal ['', 1], [out, status]
    assert_equal "#{day}/notes.md already exists\nUse --force to replace it.\n", err

    clipboard(image: PNG)
    File.chmod(0o444, bundle_path)
    out, err, status = h('context', 'img', 'diagram', '--task', 'alpha')
    assert_equal 2, status
    assert_equal "#{day}/diagram.png\n", out
    assert_equal PNG, File.binread("#{day}/diagram.png")
    assert_match(%r{\Aattach to bundle #{Regexp.escape(bundle_path)} failed: Permission denied .*; artifact kept at #{Regexp.escape(day)}/diagram\.png\nattached to task alpha\n\z}, err)
    assert_equal [['file', "#{day}/notes.md", nil], ['file', "#{day}/diagram.png", nil]], task_rows
  end

  def test_missing_or_ambiguous_task_fails_before_the_clipboard_is_read
    clipboard(text: 'x')
    [['alp', 'Ambiguous task alp: alpha, alpine'], ['zzz', 'Task not found: zzz']].each do |ref, message|
      out, err, status = h('save', '--task', ref)
      assert_equal ['', "#{message}\n", 1], [out, err, status]
      out, err, status = h('context', 'tmp', '--task', ref)
      assert_equal ['', "#{message}\n", 1], [out, err, status]
    end
    assert_empty clip_calls
    assert_empty saved_names
    assert_empty task_rows + task_rows(8)
  end

  def test_manifest_edit_rejects_invalid_text_and_keeps_it
    real = File.join(@root, 'real.txt')
    File.write(real, 'x')
    FileUtils.mkdir_p(File.dirname(bundle_path))
    File.write(bundle_path, "#{real}\n")
    edited = File.join(@root, 'edited.txt')
    File.write(edited, "#{real}\n#{@root}/missing.txt\n")

    out, err, status = h('context', 'open', EDIT_CONTENT_FILE: edited)
    assert_equal ['', 1], [out, status]
    kept = err[/edited text kept at (\S+)$/, 1]
    assert_match(%r{\A#{Regexp.escape(@home)}/\.local/share/hiiro/edits/context-bundle-\d{14}-\h{6}\.txt\z}, kept)
    assert_equal "Path does not exist: #{@root}/missing.txt; bundle unchanged, edited text kept at #{kept}\n", err
    assert_equal File.read(edited), File.read(kept)
    assert_equal "#{real}\n", File.read(bundle_path)
    assert_equal "#{real}\n", File.read(File.join(@root, 'edit-seen'))

    out, _, status = h('context', 'open', EDIT_CONTENT_FILE: edited, EDIT_EXIT: '1')
    assert_equal ["Cancelled; bundle unchanged.\n", 0], [out, status]
    File.write(edited, "#{File.basename(real)}\n")
    out, err, status = h('context', 'open', EDIT_CONTENT_FILE: edited)
    assert_equal [bundle_path + "\n", 0], [out, status], err
    assert_equal "#{real}\n", File.read(bundle_path)
  end

  def test_note_save_keeps_named_note_root_and_refuses_overwrite
    clipboard(text: 'from clipboard')
    out, err, status = h('note', 'save', 'inbox/today.md', 'typed', 'words')
    assert_equal ["#{@notes}/inbox/today.md", '', 0], [out, err, status]
    assert_equal 'typed words', File.read("#{@notes}/inbox/today.md")
    assert_empty clip_calls

    out, err, status = h('note', 'save', 'inbox/today.md')
    assert_equal ['', "#{@notes}/inbox/today.md already exists (use --force to replace it)\n", 1], [out, err, status]
    out, _, status = h('note', 'save', '--force', 'inbox/today.md')
    assert_equal ["#{@notes}/inbox/today.md", 0], [out, status]
    assert_equal 'from clipboard', File.read("#{@notes}/inbox/today.md")

    out, _, status = h('note', 'save')
    assert_equal 0, status
    assert_match(%r{\A#{Regexp.escape(@notes)}/random/note\.\h{12}\z}, out)
    assert_equal 'from clipboard', File.read(out)
  end
end
