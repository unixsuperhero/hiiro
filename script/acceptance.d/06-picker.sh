# 6. The in-process picker and a background-refreshing screen in a real
# terminal: tuios windows of $TUIOS_SESSION (HIIRO_ACCEPTANCE_TUIOS names the
# tuios binary). Every window opened here is closed on exit.
source "$(dirname "$0")/lib.sh"
sandbox
TUIOS=${HIIRO_ACCEPTANCE_TUIOS:-}
TS=${TUIOS_SESSION:-}
if [ -z "$TUIOS" ] || [ "${TUIOS_ENV:-}" != 1 ] || [ -z "$TS" ]; then
  incomplete "picker in a real terminal" "no tuios session (set TUIOS_ENV/TUIOS_SESSION and HIIRO_ACCEPTANCE_TUIOS)"
  exit 0
fi

# Editor fixture: applies the next line of $SB/editor-steps to a picker
# document ("delete:NAME", "rule:{...}", "drop-rule:TEXT", ";;"-separated)
# and logs every document it was given.
/bin/cat > "$SB/fix/editor" <<RUBY
#!$RUBY
path = ARGV.last
text = File.read(path)
File.open(File.join(ENV['SB'], 'editor.log'), 'a') { |f| f.puts "=== #{File.basename(path)}"; f.write(text) }
file = File.join(ENV['SB'], 'editor-steps')
steps = File.exist?(file) ? File.readlines(file, chomp: true) : []
step = steps.shift.to_s
File.write(file, steps.map { |s| "#{s}\n" }.join)
step.split(' ;; ').each do |op|
  case op
  when /\Adelete:(.+)\z/ then name = \$1; text = text.lines.reject { |l| l.start_with?('- [') && l.include?(%("#{name}"]  #)) }.join
  when /\Arule:(.+)\z/ then text = text.sub(/^rules:\n/, "rules:\n- #{\$1}\n")
  when /\Adrop-rule:(.+)\z/ then pat = \$1; text = text.lines.reject { |l| l.start_with?('- {') && l.include?(pat) }.join
  end
end
File.write(path, text)
RUBY
/bin/chmod +x "$SB/fix/editor"
steps() { printf '%s\n' "$@" > "$SB/editor-steps"; }

REPO_DIR="$SB/work/repo"
/bin/mkdir -p "$REPO_DIR"
CWD=$REPO_DIR sx /usr/bin/git init -q -b main . >/dev/null
CWD=$REPO_DIR sx /usr/bin/git -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16; do CWD=$REPO_DIR sx /usr/bin/git branch "feature/f$n"; done
for b in tmp/one tmp/two wip/x wip/y; do CWD=$REPO_DIR sx /usr/bin/git branch "$b"; done
refs() { CWD=$REPO_DIR sx /usr/bin/git for-each-ref --format='%(refname) %(objectname)' | sha; }
REFS_BEFORE=$(refs)

ids=()
trap 'for i in "${ids[@]}"; do "$TUIOS" run-command -s "$TS" CloseWindow "$i" >/dev/null 2>&1; done' EXIT

# win NAME DIR CMD...: a window running CMD in the sandbox environment with a
# terminal TERM, then printing its exit status and waiting. The previous
# window is closed first: an extra tiled window narrows the new one below
# COLUMNS and wraps the frame.
win() {
  local name=$1 dir=$2 env=() id
  shift 2
  [ -n "${W:-}" ] && "$TUIOS" run-command -s "$TS" CloseWindow "$W" >/dev/null 2>&1
  while IFS= read -r line; do env+=("$line"); done < <(senv)
  id=$("$TUIOS" new-window "$name" -s "$TS" --cwd "$dir" --no-focus --print-id -- \
    /usr/bin/env -i "${env[@]}" TERM=xterm-256color /bin/bash --noprofile --norc -c \
    'cd "$0" && "$@"; echo "[exit $?]"; exec /bin/sleep 900' "$dir" "$@")
  ids+=("$id")
  W=$id
}
keys() { "$TUIOS" send-keys -s "$TS" -w "$W" "$*" >/dev/null; }
text() { "$TUIOS" send-text -s "$TS" -w "$W" "$1" >/dev/null; }
waitfor() { "$TUIOS" wait-for window-output -s "$TS" -w "$W" --pattern "$1" --timeout 15000 >/dev/null; }
idle() { "$TUIOS" wait-for window-idle -s "$TS" -w "$W" --idle 600 --timeout 10000 >/dev/null; }
# screen NAME: the window's visible text, trailing blanks dropped, saved as
# NAME.txt; captured until two captures half a second apart agree, so a
# frame still being drawn is never recorded.
grab() {
  "$TUIOS" capture-pane -s "$TS" -w "$W" | LANG=en_US.UTF-8 "$RUBY" -Eutf-8 -e '
    l = $stdin.readlines.map(&:rstrip); l.pop while l.any? && l.last.empty?; puts l' | /bin/cat -s
}
screen() {
  local previous current tries=0
  idle
  current=$(grab)
  while [ $tries -lt 10 ]; do
    /bin/sleep 0.5
    previous=$current
    current=$(grab)
    [ "$current" = "$previous" ] && break
    tries=$((tries + 1))
  done
  printf '%s\n' "$current" > "$OUT/$SCENARIO-$1.txt"
  printf '%s\n' "$current"
}
screen_cut() { screen "$1" | /usr/bin/sed -E 's/ \(text kept at .*//'; }
NORM=('s#edits/picker-[0-9]{14}-[0-9a-f]{6}\.yml#edits/picker-STAMP.yml#')

PICK="ruby $REPO/bin/h-branch"

# --- a session of the multi-select picker in a 12-line window (9 rows; scrolls)
win acc06-clean "$REPO_DIR" env LINES=12 COLUMNS=100 $PICK clean -a
waitfor 'Enter choose'
want <<'EOF'
merged-branches  choices  (0 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
>  feature/f01
   feature/f02
   feature/f03
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
1/20
EOF
state "open: 20 merged branches, 9 rows visible, cursor on the first" "$WANT" screen a-open

keys / ; text feature ; keys Enter
keys Tab Tab j j j j j j j j j
want <<'EOF'
merged-branches  choices  (0 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
   feature/f10
   feature/f11
>  feature/f12
/feature  12/16
EOF
state "search /feature, Tab Tab marks f01 f02, cursor moved past the fold to f12 (scrolled)" "$WANT" screen b-search-marks-scroll

EDIT='delete:feature/f03 ;; rule:{mode: literal, field: name, pattern: "wip/x"} ;; rule:{mode: extglob, field: name, pattern: "feature/f1@(5|6)"}'
steps "$EDIT"
keys ctrl+e
waitfor 'y save'
want <<'EOF'
Save 3 new and remove 0 rules?  y save  n cancel
> + rule  extglob name feature/f1@(5|6) [picker]
  + rule  literal name wip/x [picker]
  + rule  exact feature/f03 [picker]
  exclude  feature/f03  <- exact feature/f03 [picker]
  exclude  feature/f15  <- extglob name feature/f1@(5|6) [picker]
  exclude  feature/f16  <- extglob name feature/f1@(5|6) [picker]
  exclude  wip/x  <- literal name wip/x [picker]

/feature  1/7
EOF
state "editor deletes the listed f03 row (exact) and adds a literal and a group (extglob) rule; the preview lists every effect" "$WANT" screen c-preview
state "nothing is stored before confirmation" "0" q "select count(*) from picker_exclusions"

keys n
want <<'EOF'
merged-branches  choices  (0 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
   feature/f10
   feature/f11
>  feature/f12
Cancelled; nothing saved  /feature  12/16
EOF
state "cancel keeps the query, cursor identity, and scroll" "$WANT" screen d-cancelled

steps "$EDIT"
keys ctrl+e
waitfor 'y save'
keys y
want <<'EOF'
merged-branches  choices  (4 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
   feature/f10
   feature/f11
>  feature/f12
Saved: 3 added, 0 removed  /feature  11/13
EOF
state "save refreshes the list: f03 f15 f16 gone; query, cursor identity (f12), and top row kept" "$WANT" screen e-saved
keys k k k k k k k k k k k
want <<'EOF'
merged-branches  choices  (4 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
>* feature/f01
 * feature/f02
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
   feature/f10
Saved: 3 added, 0 removed  /feature  1/13
EOF
state "the marks on f01 and f02 survived the refresh" "$WANT" screen f-marks-kept

steps 'rule:{mode: regex, field: name, pattern: "("}'
keys ctrl+e
want <<'EOF'
merged-branches  choices  (4 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
>* feature/f01
 * feature/f02
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
   feature/f10
Not saved: rule 1: invalid regex "(": end pattern with unmatched parenthesis: /(/
EOF
state "an invalid edit saves nothing and leaves the screen as it was (message cut at the kept-text path)" "$WANT" \
  screen_cut g-invalid
state "the rejected text is kept under the edits directory" "picker-STAMP.yml" /bin/sh -c "/bin/ls '$H/.local/share/hiiro/edits' | /usr/bin/sed -E 's/[0-9]{14}-[0-9a-f]{6}/STAMP/'"
steps ''
keys ctrl+e
idle
state "the next edit reopens the kept text with the error first" "# error: rule 1: invalid regex \"(\": end pattern with unmatched parenthesis: /(/" \
  /bin/sh -c "/usr/bin/awk '/^=== /{n++} n==4 && !/^=== /' '$SB/editor.log' | /usr/bin/head -1"
keys q
waitfor 'exit'
want <<'EOF'
Nothing selected.
[exit 0]
EOF
state "quitting the multi picker chooses (and deletes) nothing" "$WANT" /bin/sh -c "'$TUIOS' capture-pane -s '$TS' -w '$W' | /usr/bin/grep -E 'Nothing|exit'"
want <<'EOF'
merged-branches|picker|exact|id|["branch","$SB/work/repo","feature/f03"]
merged-branches|picker|extglob|name|feature/f1@(5|6)
merged-branches|picker|literal|name|wip/x
EOF
state "three rules stored, picker scope" "$WANT" q "select picker, scope, mode, field, pattern from picker_exclusions order by mode"

# --- reload in a new process, excluded view, restore
win acc06-reload "$REPO_DIR" env LINES=12 COLUMNS=100 $PICK clean -a
waitfor 'Enter choose'
keys / ; text f1 ; keys Enter
want <<'EOF'
merged-branches  choices  (4 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
>  feature/f10
   feature/f11
   feature/f12
   feature/f13
   feature/f14

/f1  1/5
EOF
state "a new process hides the same rows" "$WANT" screen h-reload
# The search query persists across views; clear it before the excluded view.
keys / ; "$TUIOS" send-keys -s "$TS" -w "$W" Backspace --repeat 40 >/dev/null ; keys Enter
keys ctrl+x
want <<'EOF'
merged-branches  excluded  (4 excluded)
u restore  ^E edit rules  ^X back
>  feature/f03  <- exact feature/f03 [picker]
   feature/f15  <- extglob name feature/f1@(5|6) [picker]
   feature/f16  <- extglob name feature/f1@(5|6) [picker]
   wip/x  <- literal name wip/x [picker]

1/4
EOF
state "the excluded view names the rule hiding each row" "$WANT" screen i-excluded
keys u
waitfor 'y save'
want <<'EOF'
Save 0 new and remove 1 rule?  y save  n cancel
> - rule  exact feature/f03 [picker]
  restore  feature/f03

1/2
EOF
state "restoring f03 previews removing only its exact rule" "$WANT" screen j-restore-preview
keys y
keys ctrl+x
want <<'EOF'
merged-branches  choices  (3 excluded)
Enter choose  Tab mark  ^E edit  ^X excluded
>  feature/f01
   feature/f02
   feature/f03
   feature/f04
   feature/f05
   feature/f06
   feature/f07
   feature/f08
   feature/f09
1/17
EOF
state "feature/f03 is listed again" "$WANT" screen k-restored
keys q
waitfor 'exit'

# --- the restored row is the same underlying branch
win acc06-select "$REPO_DIR" env LINES=12 COLUMNS=100 $PICK select -a
waitfor 'Enter choose'
keys / ; text f03 ; keys Enter Enter
waitfor 'exit'
want <<'EOF'
feature/f03
[exit 0]
EOF
state "choosing the restored row prints the same branch" "$WANT" /bin/sh -c "'$TUIOS' capture-pane -s '$TS' -w '$W' | /usr/bin/grep -E 'feature/f03|exit' | /usr/bin/tail -2"
state "refs are byte-identical after every picker session" "$REFS_BEFORE" refs

# --- background refresh on the same engine (h schedule ui) keeps state
seed() {
  sx ruby -e '
    require "hiiro"
    Range.new(*ARGV.map(&:to_i)).each do |n|
      Hiiro::JobOutcome.record!(run_id: "run-#{n}", definition: n.even? ? "loop-prs" : "nightly", occurrence: "o#{n}",
        finished_at: format("2026-10-13T12:%02d:30Z", n), outcome: n == 4 ? "failed" : "completed", exit_code: n == 4 ? 3 : 0, detail: "cycle #{n}")
    end' "$1" "$2"
}
seed 1 8
win acc06-jobs "$SB/work" env LINES=7 COLUMNS=120 HIIRO_UI_REFRESH=1 ruby "$REPO/bin/h-schedule" ui
waitfor 'cycle'
keys / ; text loop ; keys Enter j j
BEFORE=$(screen l-jobs-before)
seed 9 11
"$TUIOS" wait-for window-output -s "$TS" -w "$W" --pattern '4/5' --timeout 15000 >/dev/null
AFTER=$(screen m-jobs-after)
want <<'EOF'
selected same: true
rows same: true
before: /loop  3/4
after: /loop  4/5
EOF
state "three rows inserted by another process, no keys sent: selected row and visible rows unchanged, query kept, 3/4 -> 4/5" "$WANT" "$RUBY" -e 'b, a = ARGV.map(&:lines)
  puts "selected same: #{b.grep(/\A>/) == a.grep(/\A>/)}", "rows same: #{b[1..-2] == a[1..-2]}",
       "before: #{b.last.strip[/\/loop.*/]}", "after: #{a.last.strip[/\/loop.*/]}"' "$BEFORE" "$AFTER"
keys q


# --- saved records: the registry picker over a table with task scope, tags,
# and a configured action (tables.yml)
/bin/mkdir -p "$H/.config/hiiro"
/bin/cat > "$H/.config/hiiro/tables.yml" <<YML
bookmark:
  c: printf '%s|%s\n' {name} {value} >> $SB/action.log
YML
TABLES_SHA=$(sha "$H/.config/hiiro/tables.yml")
sx ruby -e '
  require "hiiro"
  alpha = Hiiro::TaskRecord.create(name: "alpha", created_at: "2026-10-13T12:00:00Z")
  t = Hiiro::Table.named("bookmark")
  t.add("docs", value: "https://docs.test/a b", short: "d", desc: "", meta: {}, task_id: alpha.id)
  t.add("wiki", value: "https://wiki.test", short: nil, desc: "", meta: {}, task_id: nil)
  t.add("tmp-scratch", value: "https://scratch.test", short: nil, desc: "", meta: {}, task_id: nil)
  Hiiro::RegistryEntry.where(name: "docs").first.tag("keep")'
registry() { q "select id, name, value, short_name, task_id from registry where resource_type = 'bookmark' order by id; select name, taggable_id from tags where taggable_type = 'RegistryEntry' order by name"; }
REGISTRY_BEFORE=$(registry)
win acc06-registry "$SB/work" env LINES=12 COLUMNS=100 ruby "$REPO/bin/h-registry" select bookmark
waitfor 'Enter choose'
steps 'rule:{mode: glob, field: name, pattern: "tmp-*"}'
keys ctrl+e
waitfor 'y save'
keys y
want <<'EOF'
registry-bookmark  choices  (1 excluded)
Enter choose  ^E edit  ^X excluded
>  bookmark        d                 docs   = https://docs.test/a b
   bookmark                          wiki   = https://wiki.test

Saved: 1 added, 0 removed  1/2
EOF
state "the registry picker hides tmp-scratch by a glob rule" "$WANT" screen n-registry
keys / ; text wiki ; keys Enter Enter
waitfor 'exit'
want <<'EOF'
wiki
[exit 0]
EOF
state "choosing prints the chosen record" "$WANT" /bin/sh -c "'$TUIOS' capture-pane -s '$TS' -w '$W' | /usr/bin/grep -E '^wiki|exit' | /usr/bin/tail -2"
state "registry values, task association, and tags unchanged by the picker" "$REGISTRY_BEFORE" registry
want <<'EOF'
global: docs,tmp-scratch,wiki
task(@alpha): docs
tags: keep
letters: o,y,c
command: printf '%s|%s\n' docs https://docs.test/a\ b >> $SB/action.log
action.log: docs|https://docs.test/a b
EOF
state "table scope, tags, and the configured action run against the same rows" "$WANT" sx ruby -e '
  require "hiiro"
  t = Hiiro::Table.named("bookmark")
  alpha = Hiiro::TaskRecord.first(name: "alpha")
  puts "global: #{t.entries(scope: Hiiro::TableScope.global).map(&:name).join(",")}"
  scope = Hiiro::TableScope.task(alpha)
  puts "#{scope.label}: #{t.entries(scope: scope).map(&:name).join(",")}"
  docs = t.find("docs")
  puts "tags: #{docs.tags.join(",")}"
  acts = Hiiro::TableActions.load
  puts "letters: #{acts.for(docs).keys.join(",")}"
  puts "command: #{acts.command("c", docs)}"
  acts.run("c", docs)
  puts "action.log: #{File.read(File.join(ENV["SB"], "action.log"))}"'
state "tables.yml is byte-identical" "$TABLES_SHA" sha "$H/.config/hiiro/tables.yml"

want <<'EOF'
PickerScreen 1
JobScreen 1
EOF
state "one Tui::State per screen" "$WANT" sx ruby -e '
  require "hiiro"
  item = Hiiro::Picker::Item.new(identity: %w[branch r a], label: "a", fields: { "name" => "a" }, value: "a")
  picker = Hiiro::PickerScreen.new(name: "x", family: "branch", items: [item], context: Hiiro::Picker::Context.none,
                                   store: Hiiro::PickerExclusion, editor: nil)
  jobs = Hiiro::JobScreen.new(definition: nil, interval: 1)
  [picker, jobs].each { |s| puts "#{s.class.name.split("::").last} #{s.instance_variables.count { |v| s.instance_variable_get(v).is_a?(Hiiro::Tui::State) }}" }'

for id in "${ids[@]}"; do "$TUIOS" run-command -s "$TS" CloseWindow "$id" >/dev/null 2>&1; done
ids=()
state "every window this scenario opened is closed" "" /bin/sh -c "'$TUIOS' list-windows -s '$TS' --json | /usr/bin/grep -o '\"name\": *\"acc06-[a-z]*\"'"
