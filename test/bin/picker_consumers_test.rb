require 'test_helper'
require 'open3'
require 'rbconfig'
require 'pty'
require 'digest'

# The real commands of each picker family on a pseudo-terminal, with saved
# exclusions in a file database: a rule saved by one invocation hides the
# choice in the next, the command acts on the chosen record, and nothing the
# rules name is changed. Only fixtures (`gh`, `open`) and git run.
class PickerConsumersTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('picker-consumers-'))
    @home = File.join(@root, 'home')
    @bin = File.join(@root, 'bin')
    @repo = File.join(@root, 'repo')
    FileUtils.mkdir_p([@home, @bin, @repo])
    { 'open' => %(#!/bin/sh\nprintf '%s\n' "$*" >> "#{@root}/open.log"\n),
      'editor' => %(#!/bin/sh\nprintf '%s\n' "$*" >> "#{@root}/editor.log"\n),
      'gh' => %(#!/bin/sh\nprintf '%s\\n' "$*" >> "#{@root}/gh.log"\ncat "#{@root}/prs.json"\n) }.each do |name, body|
      File.write(File.join(@bin, name), body)
      File.chmod(0o755, File.join(@bin, name))
    end
    @db_path = File.join(@root, 'hiiro.db')
    ruby('Hiiro::DB.setup!')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def env
    { 'HOME' => @home, 'PATH' => "#{@bin}:#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8',
      'HIIRO_TEST_DB' => "sqlite://#{@db_path}", 'TERM' => 'dumb', 'EDITOR' => File.join(@bin, 'editor'), 'LINES' => '9', 'COLUMNS' => '300' }
  end

  def ruby(code, chdir: @home)
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', "require 'hiiro'\n#{code}",
                                      chdir: chdir, unsetenv_others: true)
    assert status.success?, err
    out
  end

  def exclude(picker, mode, field, pattern, scope: 'picker', scope_key: nil)
    ruby("Hiiro::PickerExclusion.create(picker: #{picker.inspect}, scope: #{scope.inspect}, scope_key: #{scope_key.inspect}, " \
         "mode: #{mode.inspect}, field: #{field.inspect}, pattern: #{pattern.inspect}, created_at: 'now')")
  end

  # [output after the picker closed, exit status, last frame as plain rows]
  def pick(argv, keys, chdir: @home)
    output = +''
    status = nil
    PTY.spawn(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), *argv, chdir: chdir, unsetenv_others: true) do |reader, writer, pid|
      deadline = Time.now + 15
      until output.include?('Enter choose')
        flunk "picker never drew:\n#{output}" if Time.now > deadline
        output << reader.readpartial(4096) if IO.select([reader], nil, nil, 0.2)
      end
      writer.write(keys)
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      status = Process.wait2(pid).last
    end
    screen, _, after = output.rpartition("\e[?1049l")
    frame = screen.split("\e[H\e[2J").last.to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, '').split("\r\n").map(&:rstrip)
    [after.gsub("\r\n", "\n"), status.exitstatus, frame]
  end

  def git(*args) = Open3.capture2('git', '-C', @repo, *args).first

  def test_branch_pickers_hide_excluded_branches_and_never_touch_refs
    git('init', '-q', '-b', 'main')
    git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '--allow-empty', '-m', 'init')
    %w[feature/a wip/x wip/y].each { |name| git('branch', name) }
    refs = git('for-each-ref', 'refs/heads')
    exclude('branches', 'glob', 'name', 'wip/*')
    exclude('merged-branches', 'exact', 'id', JSON.generate(['branch', @repo, 'feature/a']))

    out, status, frame = pick([File.join(ROOT, 'bin/h-branch'), 'select', '-a'], "j\r", chdir: @repo)
    assert_equal ['branches  choices  (2 excluded)', 'Enter choose  ^E edit  ^X excluded', '   main', '>  feature/a', '', '', '', '', '2/2'], frame
    assert_equal ["feature/a\n", 0], [out, status]

    out, status, frame = pick([File.join(ROOT, 'bin/h-branch'), 'clean', '-a'], 'q', chdir: @repo)
    assert_equal ['merged-branches  choices  (1 excluded)', 'Enter choose  Tab mark  ^E edit  ^X excluded', '>  wip/x', '   wip/y', '', '', '', '', '1/2'], frame
    assert_equal ["Nothing selected.\n", 0], [out, status]
    assert_equal refs, git('for-each-ref', 'refs/heads')
  end

  def test_pr_picker_identifies_prs_by_repository_and_number
    File.write(File.join(@root, 'prs.json'), JSON.generate([
      { number: 7, title: 'Add picker', headRefName: 'picker', url: 'https://github.com/acme/app/pull/7' },
      { number: 7, title: 'Add picker', headRefName: 'picker', url: 'https://github.com/acme/lib/pull/7' },
    ]))
    exclude('my-prs', 'exact', 'id', '["pr","acme/app","7"]')

    out, status, frame = pick([File.join(ROOT, 'bin/h-pr'), 'select'], "\r")
    assert_equal ['my-prs  choices  (1 excluded)', 'Enter choose  ^E edit  ^X excluded', '>  #7 [picker] Add picker', '', '', '', '', '', '1/1'], frame
    assert_equal ['7', 0], [out, status]
    assert_equal ["pr list --author @me --state open --json number,title,headRefName,url\n"], File.readlines(File.join(@root, 'gh.log'))
  end

  def test_task_file_rules_apply_only_in_their_task_and_leave_files_alone
    ruby(<<~RUBY)
      %w[alpha beta].each { |name| Hiiro::TaskRecord.create(name: name) }
      %w[alpha beta].each do |name|
        home = Hiiro::TaskRecord.home_for(name)
        %w[plan.md old.bak x/run.tmp].each { |rel| FileUtils.mkdir_p(File.dirname(File.join(home, rel))); File.write(File.join(home, rel), rel) }
      end
    RUBY
    exclude('task-file', 'extglob', 'path', '**/*.@(bak|tmp)', scope: 'task', scope_key: '1')
    digest = -> { Dir.glob('**/*', base: @home).sort.map { |rel| [rel, File.file?(File.join(@home, rel)) && Digest::SHA256.file(File.join(@home, rel)).hexdigest] } }
    before = digest.call

    out, status, frame = pick([File.join(ROOT, 'exe/t'), 'file', 'open', 'alpha'], "\r")
    assert_equal ['task-file  choices  (2 excluded)  task 1 alpha', 'Enter choose  ^E edit  ^X excluded', '>  plan.md', '', '', '', '', '', '1/1'], frame
    assert_equal ['', 0], [out, status]
    assert_equal ["#{@home}/notes/work/alpha/plan.md\n"], File.readlines(File.join(@root, 'open.log'))

    _, _, frame = pick([File.join(ROOT, 'exe/t'), 'file', 'open', 'beta'], 'q')
    assert_equal ['>  old.bak', '   plan.md', '   x/run.tmp'], frame[2..4]
    assert_equal before, digest.call
  end

  def test_project_and_task_pickers_keep_records
    %w[app archive-old lib].each { |name| FileUtils.mkdir_p(File.join(@home, 'proj', name)) }
    ruby("%w[alpha alpine].each { |name| Hiiro::TaskRecord.create(name: name) }")
    exclude('projects', 'substring', 'path', 'archive')
    exclude('tasks', 'exact', 'id', '["task","2"]')

    out, status, frame = pick([File.join(ROOT, 'bin/h-project'), 'select'], "j\r")
    assert_equal ['projects  choices  (1 excluded)', 'Enter choose  ^E edit  ^X excluded',
                  "   app             [dir]    #{@home}/proj/app/", ">  lib             [dir]    #{@home}/proj/lib/"], frame[0..3]
    assert_equal ["#{@home}/proj/lib", 0], [out, status]

    out, status, frame = pick([File.join(ROOT, 'exe/t'), 'show', 'al'], "\r")
    assert_equal ['tasks  choices  (1 excluded)', 'Enter choose  ^E edit  ^X excluded', '>  alpha'], frame[0..2]
    assert_equal ["alpha [active]\n", 0], [out.lines.first, status]
    assert_equal "alpha\nalpine\n", ruby('puts Hiiro::TaskRecord.order(:id).select_map(:name)')
  end

  def test_command_and_registry_pickers_choose_records_not_rows
    %w[zqa zqb].each do |name|
      File.write(File.join(@bin, "h-#{name}"), "#!/bin/sh\necho #{name}\n")
      File.chmod(0o755, File.join(@bin, "h-#{name}"))
    end
    exclude('h-commands', 'literal', 'name', 'zqa')
    out, status, frame = pick([File.join(ROOT, 'exe/h'), 'edit', 'zq'], "\r")
    assert_equal ['h-commands  choices  (1 excluded)', 'Enter choose  ^E edit  ^X excluded', ">  zqb  external  #{@bin}/h-zqb"], frame[0..2]
    assert_match(%r{\Aediting #{@bin}/h-zqb \(}, out)
    assert_equal [0, ["#{@bin}/h-zqb\n"]], [status, File.readlines(File.join(@root, 'editor.log'))]

    ruby(<<~RUBY)
      t = Hiiro::Table.named('bookmark')
      t.add('docs', value: 'https://a.test', short: nil, desc: 'same', meta: {}, task_id: nil)
      t.add('docs-old', value: 'https://b.test', short: nil, desc: 'same', meta: {}, task_id: nil)
      Hiiro::RegistryEntry.first(name: 'docs').tag('keep')
    RUBY
    exclude('registry-bookmark', 'regex', 'name', '-old\z')
    out, status, = pick([File.join(ROOT, 'bin/h-registry'), 'select', 'bookmark'], "\r")
    assert_equal ["docs\n", 0], [out, status]
    assert_equal "docs https://a.test keep\ndocs-old https://b.test \n",
                 ruby("Hiiro::RegistryEntry.order(:id).each { |e| puts [e.name, e.value, e.tags.join(',')].join(' ') }")
  end
end
