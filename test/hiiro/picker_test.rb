require 'test_helper'
require 'yaml'

class PickerTest < Minitest::Test
  Picker = Hiiro::Picker

  # Rewrites the document text with a block, as an editor would, and parses it
  # the way InputFile does.
  class ScriptedEditor
    attr_reader :texts

    def initialize(&edit)
      @edit = edit
      @texts = []
    end

    def call(text)
      @texts << text
      result = @edit.call(text)
      parsed = YAML.safe_load(result)
      Hiiro::EditedDocument.new(path: 'picker.yml', type: :yaml, original: text, result: result, parsed: parsed)
    rescue Psych::Exception => error
      Hiiro::EditedDocument.new(path: 'picker.yml', type: :yaml, original: text, result: result, error: error)
    end

    def keep = '/kept/picker.yml'
  end

  def setup
    Hiiro::PickerExclusion.dataset.delete
    @saved = ENV.to_h.slice('LINES', 'COLUMNS')
    ENV['LINES'] = '9'
    ENV['COLUMNS'] = '60'
  end

  def teardown
    %w[LINES COLUMNS].each { |name| ENV[name] = @saved[name] }
  end

  def file(path, base: '/repo') = Picker.item(:file, base, path, label: path, value: path, path: path, name: File.basename(path), base: base)
  def branch(name, repo: '/src/app', label: name) = Picker.branch_item(name, repo: repo, label: label)

  def rule(mode, field, pattern, family: 'file', scope: 'picker', scope_key: nil, picker: 'files')
    Picker::Rule.new(picker: picker, scope: scope, scope_key: scope_key, mode: mode, field: field, pattern: pattern).validate!(family)
  end

  def invalid(&block) = assert_raises(Picker::Invalid, &block).message

  def screen(items, name: 'files', family: 'file', context: Picker::Context.none, editor: nil, multi: false)
    Hiiro::PickerScreen.new(name: name, family: family, items: items, context: context, store: Hiiro::PickerExclusion,
                            editor: editor || ScriptedEditor.new { |text| text }, multi: multi)
  end

  def press(screen, *keys) = keys.each { |key| screen.handle_key(key) }
  def frame(screen) = screen.frame(rows: 9, cols: 60)
  def rows = Hiiro::PickerExclusion.order(:id).all.map { |row| [row.picker, row.scope, row.scope_key, row.mode, row.field, row.pattern] }

  def test_glob_and_extglob_match_whole_normalized_paths
    paths = %w[scratch.md a.bak notes/a.bak notes/deep/b.tmp notes/c.md archive/x archive/x/y Readme.md]
    matched = lambda do |mode, pattern|
      paths.select { |path| rule(mode, 'path', pattern).matches?(file(path)) }
    end

    assert_equal %w[a.bak notes/a.bak], matched.call('glob', '**/*.bak')
    assert_equal %w[a.bak], matched.call('glob', '*.bak')
    assert_equal %w[archive/x], matched.call('glob', 'archive/*')
    assert_equal %w[archive/x archive/x/y], matched.call('glob', 'archive/**')
    assert_equal %w[a.bak notes/a.bak notes/deep/b.tmp], matched.call('extglob', '**/*.@(bak|tmp)')
    assert_equal %w[notes/a.bak archive/x], matched.call('extglob', '*/!(*.md)')
    assert_equal %w[notes/a.bak], matched.call('extglob', 'notes/+([a-c]).bak')
    assert_equal %w[scratch.md], matched.call('literal', './scratch.md')
    assert_equal [], matched.call('glob', 'readme.md')
    assert_equal %w[Readme.md], matched.call('regex', '(?i)^readme')
    assert_equal %w[notes/a.bak notes/deep/b.tmp notes/c.md], matched.call('substring', 'notes/')
  end

  def test_rules_reject_unknown_fields_modes_scopes_and_malformed_patterns
    assert_equal 'unknown field "label" for file items; use path, name, base', invalid { rule('glob', 'label', '*') }
    assert_equal 'unknown mode "fuzzy"; use exact, literal, substring, regex, glob, extglob', invalid { rule('fuzzy', 'path', 'x') }
    assert_equal 'unknown scope "team"; use picker, task, project, global', invalid { rule('glob', 'path', 'x', scope: 'team') }
    assert_equal 'exact rules match field id, not "path"', invalid { rule('exact', 'path', '["file"]') }
    assert_equal 'exact pattern must be a JSON list of strings: main', invalid { rule('exact', 'id', 'main') }
    assert_match(/\Ainvalid regex "\^draft-\(\[0-9\]\+": end pattern with unmatched parenthesis/, invalid { rule('regex', 'path', '^draft-([0-9]+') })
    assert_equal 'invalid extglob "**/*.@(bak|tmp": unclosed ( in "**/*.@(bak|tmp"', invalid { rule('extglob', 'path', '**/*.@(bak|tmp') }
    assert_equal 'invalid extglob "@(a/b)": / inside an extglob list in "@(a/b)"', invalid { rule('extglob', 'path', '@(a/b)') }
    assert_equal 'literal rule needs a non-empty text pattern', invalid { rule('literal', 'path', '') }
  end

  def test_deleting_rows_excludes_only_snapshot_identities_and_duplicate_labels_stay_distinct
    plan_a = Picker.saved_item(store: 'portfolio', id: 41, name: 'Plan')
    plan_b = Picker.saved_item(store: 'portfolio', id: 42, name: 'Plan')
    hidden = Picker.saved_item(store: 'portfolio', id: 43, name: 'Plan old')
    document = Picker::Document.new(picker: 'docs', family: 'saved', snapshot: [plan_a, plan_b], rules: [], context: Picker::Context.none)
    assert_equal <<~TEXT, document.text.lines.drop(6).join
      scope: picker
      items:
      - ["saved","portfolio","41"]  # Plan
      - ["saved","portfolio","42"]  # Plan
      rules:
    TEXT

    change = document.change(YAML.safe_load(document.text.sub(%(- ["saved","portfolio","42"]  # Plan\n), '')))
    assert_equal [[nil, 'docs', 'picker', nil, 'exact', 'id', '["saved","portfolio","42"]', 'Plan']],
                 change.add.map { |r| [r.id, r.picker, r.scope, r.scope_key, r.mode, r.field, r.pattern, r.label] }
    assert_equal [], change.remove
    assert_equal [false, true, false], [plan_a, plan_b, hidden].map { |item| change.add.first.matches?(item) }

    renamed = Picker.saved_item(store: 'portfolio', id: 42, name: 'Plan (renamed)')
    assert change.add.first.matches?(renamed)

    assert_equal 'item 1: ["saved", "portfolio", "43"] is not one of the listed items',
                 invalid { document.change('items' => [%w[saved portfolio 43]], 'rules' => nil) }
  end

  def test_rule_edits_scopes_and_global_choice_are_explicit
    task = Picker::Context.new(task_id: '3', task_name: 'alpha', project: 'rehiiro')
    kept = Picker::Rule.new(id: 7, picker: 'files', scope: 'task', scope_key: '3', mode: 'glob', field: 'path', pattern: '*.tmp')
    gone = Picker::Rule.new(id: 8, picker: 'files', scope: 'picker', mode: 'substring', field: 'name', pattern: 'generated')
    document = Picker::Document.new(picker: 'files', family: 'file', snapshot: [], rules: [kept, gone], context: task)
    assert_equal <<~TEXT, document.text.lines.drop(6).join
      scope: task
      items:
      rules:
      - {id: 7, scope: task, mode: glob, field: path, pattern: "*.tmp"}
      - {id: 8, scope: picker, mode: substring, field: name, pattern: "generated"}
    TEXT

    change = document.change(YAML.safe_load(<<~YAML))
      scope: task
      rules:
      - {id: 7, scope: task, mode: glob, field: path, pattern: "**/*.tmp"}
      - {mode: regex, field: name, pattern: "^draft-[0-9]+", scope: project}
      - {mode: extglob, field: path, pattern: "**/*.@(bak|tmp)", scope: global}
    YAML
    assert_equal [%w[task 3 glob path **/*.tmp], ['project', 'rehiiro', 'regex', 'name', '^draft-[0-9]+'], [nil, nil, 'extglob', 'path', '**/*.@(bak|tmp)'].tap { |r| r[0] = 'global' }],
                 change.add.map { |r| [r.scope, r.scope_key, r.mode, r.field, r.pattern] }
    assert_equal [7, 8], change.remove.map(&:id)

    none = Picker::Document.new(picker: 'files', family: 'file', snapshot: [], rules: [], context: Picker::Context.none)
    assert_equal 'rule 1: scope task is not available: no current task',
                 invalid { none.change('rules' => [{ 'mode' => 'glob', 'field' => 'path', 'pattern' => '*', 'scope' => 'task' }]) }
    assert_equal 'rule 1: no rule with id 99 here', invalid { none.change('rules' => [{ 'id' => 99, 'mode' => 'glob', 'field' => 'path', 'pattern' => '*' }]) }
    assert_equal 'unknown keys: exclude', invalid { none.change('exclude' => []) }
  end

  def test_saved_rules_apply_by_picker_and_scope_and_hide_future_items
    one = Picker::Context.new(task_id: '1', task_name: 'one', project: 'app')
    two = Picker::Context.new(task_id: '2', task_name: 'two', project: 'lib')
    add = lambda do |*rules|
      Hiiro::PickerExclusion.apply!(Picker::Change.new(add: rules, remove: []))
    end
    add.call(rule('glob', 'path', '**/*.bak', scope: 'task', scope_key: '1'),
             rule('literal', 'name', 'notes.md', scope: 'project', scope_key: 'lib'),
             rule('substring', 'path', 'tmp', scope: 'picker'),
             rule('extglob', 'path', '**/*.@(log|out)', scope: 'global', picker: 'other'))

    visible = lambda do |picker, context, items|
      rules = Hiiro::PickerExclusion.applicable(picker, context)
      items.reject { |item| rules.any? { |r| r.matches?(item) } }.map(&:label)
    end
    later = [file('a.bak'), file('x/new.bak'), file('notes.md'), file('tmp/a'), file('run.log'), file('keep.rb')]
    assert_equal %w[notes.md keep.rb], visible.call('files', one, later)
    assert_equal %w[a.bak x/new.bak keep.rb], visible.call('files', two, later)
    assert_equal %w[a.bak x/new.bak notes.md keep.rb], visible.call('files', Picker::Context.none, later)
    assert_equal %w[a.bak x/new.bak notes.md tmp/a keep.rb], visible.call('elsewhere', one, later)
    assert_equal [%w[files task 1 glob path **/*.bak], %w[files project lib literal name notes.md],
                  ['files', 'picker', nil, 'substring', 'path', 'tmp'], ['other', 'global', nil, 'extglob', 'path', '**/*.@(log|out)']], rows
  end

  def test_edit_previews_saves_and_keeps_query_position_and_visible_marks
    items = %w[a.md b.bak c.md d.bak e.md].map { |path| file(path) }
    editor = ScriptedEditor.new do |text|
      text.sub(%(- ["file","/repo","c.md"]  # c.md\n), '').sub("rules:\n", "rules:\n- {mode: glob, field: path, pattern: \"**/*.bak\"}\n")
    end
    picker = screen(items, editor: editor, multi: true)
    press(picker, '/', '.', 'm', 'd', :enter, "\t")
    assert_equal ['files  choices  (0 excluded)', 'Enter choose  Tab mark  ^E edit  ^X excluded',
                  ' * a.md', '>  c.md', '   e.md', '', '', '', '/.md  2/3'], frame(picker)

    press(picker, "\u0005")
    assert_equal 1, editor.texts.length
    assert_includes editor.texts.first, %(- ["file","/repo","a.md"]  # a.md\n- ["file","/repo","c.md"]  # c.md\n- ["file","/repo","e.md"]  # e.md\nrules:\n)
    assert_equal ['Save 2 new and remove 0 rules?  y save  n cancel',
                  '> + rule  glob path **/*.bak [picker]',
                  '  + rule  exact c.md [picker]',
                  '  exclude  b.bak  <- glob path **/*.bak [picker]',
                  '  exclude  c.md  <- exact c.md [picker]',
                  '  exclude  d.bak  <- glob path **/*.bak [picker]', '', '', '/.md  1/5'], frame(picker)
    assert_equal [], rows

    press(picker, 'y')
    assert_equal ['files  choices  (3 excluded)', 'Enter choose  Tab mark  ^E edit  ^X excluded',
                  ' * a.md', '>  e.md', '', '', '', '', 'Saved: 2 added, 0 removed  /.md  2/2'], frame(picker)
    assert_equal [['files', 'picker', nil, 'glob', 'path', '**/*.bak'], ['files', 'picker', nil, 'exact', 'id', '["file","/repo","c.md"]']], rows

    # A later invocation with a newly arrived .bak: the saved rules hide it too.
    again = screen(items + [file('f.bak')])
    assert_equal ['files  choices  (4 excluded)', 'Enter choose  ^E edit  ^X excluded', '>  a.md', '   e.md', '', '', '', '', '1/2'], frame(again)

    # The excluded view keeps the query; u restores the row under the cursor.
    press(picker, "\u0018")
    assert_equal ['files  excluded  (3 excluded)', 'u restore  ^E edit rules  ^X back',
                  '>  c.md  <- exact c.md [picker]', '', '', '', '', '', '/.md  1/1'], frame(picker)
    press(picker, 'u')
    assert_equal ['Save 0 new and remove 1 rule?  y save  n cancel', '> - rule  exact c.md [picker]',
                  '  restore  c.md', '', '', '', '', '', '/.md  1/2'], frame(picker)
    press(picker, 'y', "\u0018")
    assert_equal [['files', 'picker', nil, 'glob', 'path', '**/*.bak']], rows
    assert_equal ['files  choices  (2 excluded)', 'Enter choose  Tab mark  ^E edit  ^X excluded',
                  ' * a.md', '   c.md', '>  e.md', '', '', '', '/.md  3/3'], frame(picker)
  end

  def test_invalid_edits_change_nothing_and_reopen_the_kept_text
    items = [branch('main'), branch('wip/x')]
    attempts = ["scope: picker\nrules:\n- {mode: regex, field: name, pattern: \"(\"}\n", "items: [unclosed\n"]
    editor = ScriptedEditor.new { |_text| attempts.shift || "scope: picker\nitems:\n- [\"branch\",\"/src/app\",\"main\"]\nrules:\n" }
    picker = screen(items, name: 'branches', family: 'branch', editor: editor)

    press(picker, "\u0005")
    assert_equal 'Not saved: rule 1: invalid regex "(": end pattern with unmatched parenthesis: /(/ (text kept at /kept/picker.yml; ^E reopens it)',
                 picker.state.message
    press(picker, "\u0005")
    assert_equal "# error: rule 1: invalid regex \"(\": end pattern with unmatched parenthesis: /(/\nscope: picker\nrules:\n- {mode: regex, field: name, pattern: \"(\"}\n",
                 editor.texts[1]
    assert_equal "Not saved: (<unknown>): did not find expected ',' or ']' while parsing a flow sequence at line 1 column 8 (text kept at /kept/picker.yml; ^E reopens it)",
                 picker.state.message
    assert_equal [], rows

    press(picker, "\u0005", 'n')
    assert_equal ['branches  choices  (0 excluded)', 'Enter choose  ^E edit  ^X excluded', '>  main', '   wip/x', '', '', '', '',
                  'Cancelled; nothing saved  1/2'], frame(picker)
    assert_equal [], rows
  end

  def test_real_editor_round_trips_the_document_through_input_file
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'editor')
      File.write(script, "#!/bin/sh\nsed -i.orig '/wip\\/x/d' \"$1\"\n")
      File.chmod(0o755, script)
      saved = ENV['EDITOR']
      ENV['EDITOR'] = script
      picker = screen([branch('main'), branch('wip/x'), branch('wip/y')], name: 'branches', family: 'branch',
                      editor: Picker::Editor.new)
      press(picker, "\u0005", 'y')
      assert_equal [['branches', 'picker', nil, 'exact', 'id', '["branch","/src/app","wip/x"]']], rows
      assert_equal ['>  main', '   wip/y'], frame(picker)[2..3]
    ensure
      ENV['EDITOR'] = saved
    end
  end

  def test_items_from_each_family_carry_stable_identities
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)
      FileUtils.mkdir_p(File.join(dir, 'home/notes'))
      File.write(File.join(dir, 'home/notes/a.md'), '')
      entry = Hiiro::Catalog::Entry.new(name: 'pr', kind: :external, source: '/bin/h-pr', aliases: [], shadowed: [])
      task = Struct.new(:id, :name, :tree).new(42, 'alpha', 'alpha/main')
      pr = Struct.new(:number, :repo, :head_branch, :title, :reference).new(7, 'acme/app', 'fix', 'Fix it', nil)
      assert_equal [%w[command external pr /bin/h-pr], %w[file notes/a.md], %w[file etc/hosts], %w[task 42], %w[project rehiiro],
                    %w[branch /src/app main], %w[pr acme/app 7], %w[saved registry 5]],
                   [Picker.command_item(entry).identity, Picker.file_item(File.join(dir, 'home/notes/a.md'), base: File.join(dir, 'home')).identity.values_at(0, 2),
                    Picker.file_item('/etc/hosts', base: dir).identity.values_at(0, 2).tap { |id| id[1] = id[1].sub('private/', '') },
                    Picker.task_item(task).identity, Picker.project_item('rehiiro', '/p/rehiiro').identity,
                    Picker.branch_item('main', repo: '/src/app').identity, Picker.pr_record_item(pr).identity,
                    Picker.saved_item(store: 'registry', id: 5, name: 'docs').identity]
    end
  end
end
