# 2. Synthetic legacy stores through the explicit plan/migrate interface.
source "$(dirname "$0")/lib.sh"
sandbox
C="$H/.config/hiiro"
/bin/mkdir -p "$C/tasks" "$C/pins"
/bin/cat > "$C/todo.yml" <<'Y'
next_id: 50
todos:
- id: 7
  text: legacy seven
  status: started
  tags: urgent
- id: 8
  text: legacy eight
Y
/bin/cat > "$C/links.yml" <<'Y'
- id: 22
  url: https://example.test/doc
  description: the doc
  shorthand: d
Y
/bin/cat > "$C/tasks/tasks.yml" <<'Y'
tasks:
- id: 12
  name: alpha
  status: waiting
  tree: /tmp/alpha-tree
Y
/bin/cat > "$C/tasks/task_alpha.yml" <<'Y'
windows:
- index: 2
  name: docs
saved_at: '2026-01-01T10:00:00Z'
resources:
- id: 40
  kind: url
  target: https://example.test/spec
  label: spec
Y
/bin/cat > "$C/pinned_prs.yml" <<'Y'
- id: 30
  repo: one/repo
  number: 1
  title: first
- id: 31
  repo: two/repo
  number: 1
  title: second
Y
/bin/cat > "$C/tags.yml" <<'Y'
task:
  alpha: [work]
link:
  '22': [doc]
pinned_pr:
  '31': [review]
Y
/bin/cat > "$C/pins/h-link" <<'Y'
number-string: '42'
number: 42
flag: false
list: [1, '2']
Y
/bin/cat > "$C/reminders.yml" <<'Y'
- message: stretch
  interval: 30m
  sound: Glass
  enabled: true
  once: false
  last_triggered: '2026-10-01T09:00:00Z'
- message: stretch
  interval: 30m
  sound: Glass
  enabled: true
  once: false
  last_triggered: '2026-10-01T09:00:00Z'
Y
/bin/cat > "$C/tables.yml" <<'Y'
bookmark:
  c: cd {value}
Y
/bin/cat > "$C/services.yml" <<'Y'
web:
  base_dir: app
  start: [ruby, -run, -e, httpd]
Y
printf 'unknown \0 bytes\n' > "$C/mystery.dat"

# Condenses `h db plan|migrate` output: one line per report entry and error
# (with FULL=1 also per selected and available source); other lines verbatim.
/bin/cat > "$SB/summ.rb" <<'RB'
require 'json'
text = $stdin.read
docs = []
rest = text.gsub(/^[\[{]\n.*?^[\]}]\n/m) { |doc| docs << JSON.parse(doc); '' }
docs.each do |doc|
  if doc.is_a?(Hash) && doc.key?('manifest')
    ENV['FULL'] && doc['sources'].each { |s| puts "source #{s['store']} #{s['path']} rows=#{s['rows']}" }
    ENV['FULL'] && (doc['available_sources'] || []).each { |s| puts "available #{s.is_a?(Hash) ? s.values_at('store', 'path', 'selected').compact.join(' ') : s}" }
    doc['report'].each { |r| puts "plan-report #{r.to_a.reject { |k, _| k == 'checksum' }.map { |k, v| "#{k}=#{v}" }.join(' ')}" }
    doc['errors'].each { |e| puts "error #{e}" }
  else
    Array(doc).each { |r| puts "report #{r.to_a.reject { |k, _| k == 'checksum' }.map { |k, v| "#{k}=#{v}" }.join(' ')}" }
  end
end
print rest
RB
summ() { local out code; out=$("$@" 2>&1); code=$?; printf '%s\n' "$out" | "$RUBY" "$SB/summ.rb"; return $code; }
summ_full() { FULL=1 summ "$@"; }
# The database is in WAL mode; sqlite3 -readonly cannot open it before a -shm
# file exists, so reads here use query_only instead.
q() { /usr/bin/sqlite3 -cmd 'PRAGMA query_only=1' -separator '|' "$DB" "$@"; }
LEGACY="todo.yml links.yml tasks/tasks.yml tasks/task_alpha.yml pinned_prs.yml tags.yml pins/h-link reminders.yml"
KEEP="$LEGACY tables.yml services.yml mystery.dat"
hashes() { (cd "$C" && for f in $KEEP; do printf '%s %s\n' "$(sha "$f")" "$f"; done; /bin/ls -A "$C" "$C/tasks" "$C/pins" | /usr/bin/grep -c '\.bak$'); }
hb ping > /dev/null 2>&1   # first startup: creates the empty database only
BEFORE=$(hashes)

# The canonical records every later check compares against (IDs, relations, typed values).
records() {
  q "select 'todo', id, text, status, coalesce(tags,'') from todos order by id"
  q "select 'link', case when id = 22 then id else 'n' end, value, description, coalesce(short_name,'') from registry where resource_type = 'link' and name not in ('flag','list','number','number-string') order by id"
  q "select 'task', id, name, status, tree, metadata_json from tasks order by id"
  q "select 'resource', id, task_id, kind, target, label from task_resources order by id"
  q "select 'pr', id, repo, number, title from prs order by id"
  q "select 'tag', taggable_type, taggable_id, name from tags order by id"
  q "select 'pin', resource_type, name, value from registry where resource_type = 'link' and name in ('flag','list','number','number-string') order by name"
  q "select 'reminder', id, message, interval, sound, enabled, once, last_triggered from reminders order by id"
}
RECORDS='todo|7|legacy seven|started|urgent
todo|8|legacy eight|not_started|
link|22|https://example.test/doc|the doc|d
task|12|alpha|waiting|/tmp/alpha-tree|{"windows":[{"index":2,"name":"docs"}],"saved_at":"2026-01-01T10:00:00Z"}
resource|40|12|url|https://example.test/spec|spec
pr|30|one/repo|1|first
pr|31|two/repo|1|second
tag|Task|alpha|work
tag|RegistryEntry|22|doc
tag|PinnedPr|31|review
pin|link|flag|false
pin|link|list|[1,"2"]
pin|link|number|42
pin|link|number-string|42
reminder|1|stretch|30m|Glass|1|0|2026-10-01T09:00:00Z
reminder|2|stretch|30m|Glass|1|0|2026-10-01T09:00:00Z'

check "plan lists every legacy source as ready; definitions and the unknown file are not selected" "$(cat <<'E'
source todos $SB/home/.config/hiiro/todo.yml rows=2
source links $SB/home/.config/hiiro/links.yml rows=1
source pinned_prs $SB/home/.config/hiiro/pinned_prs.yml rows=2
source tasks $SB/home/.config/hiiro/tasks/task_alpha.yml rows=2
source tasks $SB/home/.config/hiiro/tasks/tasks.yml rows=1
source pins $SB/home/.config/hiiro/pins/h-link rows=4
source reminders $SB/home/.config/hiiro/reminders.yml rows=2
source tags $SB/home/.config/hiiro/tags.yml rows=3
available todos $SB/home/.config/hiiro/todo.yml
available links $SB/home/.config/hiiro/links.yml
available pinned_prs $SB/home/.config/hiiro/pinned_prs.yml
available tasks $SB/home/.config/hiiro/tasks/task_alpha.yml
available tasks $SB/home/.config/hiiro/tasks/tasks.yml
available pins $SB/home/.config/hiiro/pins/h-link
available reminders $SB/home/.config/hiiro/reminders.yml
available tags $SB/home/.config/hiiro/tags.yml
plan-report source=$SB/home/.config/hiiro/todo.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/links.yml status=ready rows=1
plan-report source=$SB/home/.config/hiiro/pinned_prs.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tasks/task_alpha.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tasks/tasks.yml status=ready rows=1
plan-report source=$SB/home/.config/hiiro/pins/h-link status=ready rows=4
plan-report source=$SB/home/.config/hiiro/reminders.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tags.yml status=ready rows=3
Plan only; no records imported. Definitions, preferences and artifacts are excluded.
[exit 0]
E
)" summ_full hb db plan

migration_line() { hb db status 2>&1 | /usr/bin/grep '^Migration:'; }
counts() {
  q "select (select count(*) from todos), (select count(*) from registry where resource_type = 'link' and id = 22), (select count(*) from tasks), (select count(*) from prs), (select count(*) from tags), (select count(*) from registry where resource_type = 'link' and name in ('flag','list','number','number-string')), (select count(*) from reminders)"
  migration_line
}
state "startup and plan created the database but imported nothing" "0|0|0|0|0|0|0
Migration: not run" counts

/bin/cat > "$C/pins/h-link.yml" <<'Y'
number: 43
Y
check "a conflicting pin variant is rejected before anything is imported" "error Conflicting source variants: pins/h-link
Migration rejected; no records imported and all sources retained.
[exit 1]" summ hb db plan --only=pins
/bin/rm "$C/pins/h-link.yml"

sx ruby -e 'require "hiiro"; Hiiro::DB.connection[:todos].insert(id: 7, text: "canonical seven")'
check "a canonical record that differs from the legacy row is a reported conflict, never overwritten" "error Canonical conflict: todos/7 fields text, status, tags
Migration rejected; no records imported and all sources retained.
[exit 1]" summ hb db migrate --only=todos
state "the conflicting canonical row is unchanged and nothing else was imported" "7|canonical seven
0" q "select id, text from todos" "select count(*) from migration_sources"
sx ruby -e 'require "hiiro"; Hiiro::DB.connection[:todos].where(id: 7).delete'

check "migrate imports every selected source and verifies it through a fresh connection" "$(cat <<'E'
plan-report source=$SB/home/.config/hiiro/todo.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/links.yml status=ready rows=1
plan-report source=$SB/home/.config/hiiro/pinned_prs.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tasks/task_alpha.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tasks/tasks.yml status=ready rows=1
plan-report source=$SB/home/.config/hiiro/pins/h-link status=ready rows=4
plan-report source=$SB/home/.config/hiiro/reminders.yml status=ready rows=2
plan-report source=$SB/home/.config/hiiro/tags.yml status=ready rows=3
report source=$SB/home/.config/hiiro/todo.yml status=verified rows=2
report source=$SB/home/.config/hiiro/links.yml status=verified rows=1
report source=$SB/home/.config/hiiro/pinned_prs.yml status=verified rows=2
report source=$SB/home/.config/hiiro/tasks/task_alpha.yml status=verified rows=2
report source=$SB/home/.config/hiiro/tasks/tasks.yml status=verified rows=1
report source=$SB/home/.config/hiiro/pins/h-link status=verified rows=4
report source=$SB/home/.config/hiiro/reminders.yml status=verified rows=2
report source=$SB/home/.config/hiiro/tags.yml status=verified rows=3
Selected import verified. All source files retained unchanged.
[exit 0]
E
)" summ hb db migrate
state "imported records keep IDs, relations, text pins in the command table, recurrence, and duplicate reminders" "$RECORDS" records
state "status reports the verified import" "Migration: selected imports verified" migration_line
state "legacy sources, definitions, and the unknown file are byte-identical; no .bak was written" "$BEFORE" hashes

check "repeating migrate replays nothing" "$(cat <<'E'
plan-report source=$SB/home/.config/hiiro/todo.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/links.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/pinned_prs.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/tasks/task_alpha.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/tasks/tasks.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/pins/h-link status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/reminders.yml status=previously-applied canonical_changes_or_deletions=0
plan-report source=$SB/home/.config/hiiro/tags.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/todo.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/links.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/pinned_prs.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/tasks/task_alpha.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/tasks/tasks.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/pins/h-link status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/reminders.yml status=previously-applied canonical_changes_or_deletions=0
report source=$SB/home/.config/hiiro/tags.yml status=previously-applied canonical_changes_or_deletions=0
Selected import verified. All source files retained unchanged.
[exit 0]
E
)" summ hb db migrate

# Registry rows with a task association, tags, and table actions from tables.yml.
sx ruby -e 'require "hiiro"
  t = Hiiro::Table.named("bookmark")
  e = t.add("wiki", value: "/srv/wiki docs", desc: "team wiki", task_id: 12)
  e.tag("keep", "ops")
  t.add("plain", value: "/srv/plain")'
table_view() {
  sx ruby -e 'require "hiiro"
    t = Hiiro::Table.named("bookmark")
    task = Hiiro::TableScope.task(Hiiro::TaskRecord[12])
    puts "#{task.label}: #{t.entries(scope: task).map(&:name).join(",")} (global #{t.count})"
    wiki = t.find("wiki")
    puts "wiki task_id=#{wiki.task_id} tags=#{wiki.tags.join(",")}"
    acts = Hiiro::TableActions.load
    puts "letters #{acts.for(wiki).keys.join(",")}"
    puts "c -> #{acts.command("c", wiki)}"'
}
TABLE_VIEW="task(@alpha): wiki (global 2)
wiki task_id=12 tags=keep,ops
letters o,y,c
c -> cd /srv/wiki\\ docs
[exit 0]"
check "a later process sees the task association, tags, and the configured action" "$TABLE_VIEW" table_view

# Later canonical changes, then a repeated migration: the snapshot is not replayed.
hb todo done 8 > /dev/null 2>&1
check "after canonical changes, repeating migrate reports them and keeps them" "plan-report source=\$SB/home/.config/hiiro/todo.yml status=previously-applied canonical_changes_or_deletions=1
report source=\$SB/home/.config/hiiro/todo.yml status=previously-applied canonical_changes_or_deletions=1
Selected import verified. All source files retained unchanged.
[exit 0]" summ hb db migrate --only=todos
state "todo 8 keeps its later status" "8|legacy eight|done" q "select id, text, status from todos where id = 8"

# Independent concurrent writers, released together by one gate file.
gate="$SB/gate"
pids=()
launch_all() {
  local i=0
  for spec in "h-registry add bookmark conc1 /srv/c1" "h-registry add bookmark conc2 /srv/c2" "h-registry add bookmark conc3 /srv/c3" \
              "h-todo add concurrent one" "h-todo add concurrent two" "h-link add https://example.test/new new link" "h-todo skip 7"; do
    i=$((i + 1))
    set -- $spec
    local bin=$1; shift
    (CWD="$SB/work" sx /bin/sh -c 'while [ ! -e "$SB/gate" ]; do sleep 0.01; done; exec ruby "$@"' sh "$REPO/bin/$bin" "$@" > "$SB/writer-$i.log" 2>&1; echo $? > "$SB/writer-$i.exit") &
    pids+=($!)
  done
  sleep 1
  : > "$gate"
  for pid in "${pids[@]}"; do wait "$pid"; done
  /bin/cat "$SB"/writer-*.exit | /usr/bin/sort | /usr/bin/uniq -c | /usr/bin/awk '{ print $1 " writers exited " $2 }'
}
check "seven writers started together all succeed" "7 writers exited 0
[exit 0]" launch_all
after_writers() {
  q "select name, value, coalesce(task_id,''), resource_type from registry where resource_type = 'bookmark' order by name"
  # The two concurrent todos may take 50 and 51 in either order.
  q "select id, text, status from todos where id < 50 order by id"
  q "select group_concat(id) from (select id from todos where id >= 50 order by id)"
  q "select text, status from todos where id >= 50 order by text"
  q "select case when id = 22 then id else 'n' end, value, description from registry where resource_type = 'link' and name not in ('flag','list','number','number-string') order by id"
  q "select r.name, group_concat(t.name) from registry r join tags t on t.taggable_type = 'RegistryEntry' and t.taggable_id = cast(r.id as text) group by r.name"
}
AFTER_WANT="conc1|/srv/c1||bookmark
conc2|/srv/c2||bookmark
conc3|/srv/c3||bookmark
plain|/srv/plain||bookmark
wiki|/srv/wiki docs|12|bookmark
7|legacy seven|skip
8|legacy eight|done
50,51
concurrent one|not_started
concurrent two|not_started
22|https://example.test/doc|the doc
n|https://example.test/new|new link
d|doc
wiki|keep,ops"
state "every concurrent write landed and no earlier row was replaced" "$AFTER_WANT" after_writers
# Full view; the two concurrent todos are shown by text since their ids race.
final_view() {
  after_writers
  records | /usr/bin/sed -E 's/^todo\|5[01]\|/todo|5x|/' | "$RUBY" -e 'lines = $stdin.readlines
    racing = lines.select { |l| l.start_with?("todo|5x|") }.sort
    print lines.map { |l| l.start_with?("todo|5x|") ? racing.shift : l }.join'
}
check "tables.yml is still byte-identical after every writer" "$(printf '%s' "$BEFORE" | /usr/bin/grep ' tables.yml$')
[exit 0]" sh -c "cd '$C' && /usr/bin/shasum -a 256 tables.yml | /usr/bin/awk '{ print \$1 \" \" \$2 }'"

# Restart: a fresh process reloads the same records and table configuration.
hb db status > /dev/null 2>&1
FINAL="$(printf '%s\n' "$AFTER_WANT")
$(printf '%s\n' "$RECORDS" | /usr/bin/sed -e 's/^todo|7|legacy seven|started|urgent$/todo|7|legacy seven|skip|urgent/' -e 's/^todo|8|legacy eight|not_started|$/todo|8|legacy eight|done|/' \
  -e 's#^link|22|.*#&\nlink|n|https://example.test/new|new link|#' -e 's/^todo|8|.*/&\ntodo|5x|concurrent one|not_started|\ntodo|5x|concurrent two|not_started|/' -e 's/^tag|PinnedPr|31|review$/&\ntag|RegistryEntry|27|keep\ntag|RegistryEntry|27|ops/')"
state "a fresh process after all writers reloads the same rows" "$FINAL" final_view
check "the table view after reload keeps the task scope, tags, and action (now 5 rows globally)" "${TABLE_VIEW/global 2/global 5}" table_view

# Canonical export, then restore into an empty database under a second HOME.
check "export writes a new canonical file and refuses to overwrite it" "Canonical export: \$SB/export.json
Full typed rows, IDs, relations, import ledger and allocator state saved; existing files never overwritten.
[exit 0]" hb db export "$SB/export.json"
check "a second export to the same path is refused" "Export rejected: File exists @ rb_sysopen - \$SB/export.json
[exit 1]" hb db export "$SB/export.json"
H2="$SB/home2"; /bin/mkdir -p "$H2"
in_home2() { ENVX=("HOME=$H2"); "$@"; local c=$?; ENVX=(); return $c; }
DB1=$DB
# Restore prints one row per record; this condenses it to "TABLE STATUS COUNT".
restore_summary() {
  in_home2 hb db restore "$SB/export.json" | "$RUBY" -e 'rows = $stdin.readlines
    counts = Hash.new(0)
    rows.each { |l| f = l.split; f.size == 3 && %w[restored identical].include?(f[2]) ? counts[[f[0], f[2]]] += 1 : (puts l unless l =~ /\A(table |-+$)/) }
    counts.each { |(t, st), n| puts "#{t} #{st} #{n}" }'
}
RESTORED="(52 rows)
Recovery verified. Later canonical writes retained; no sources overwritten.
tasks restored 1
prs restored 2
registry restored 11
todos restored 4
reminders restored 2
tags restored 5
task_resources restored 1
schema_migrations restored 1
migration_sources restored 8
migration_rows restored 17
[exit 0]"
check "restore into an empty second database inserts every exported row with its original id" "$RESTORED" restore_summary
restored() { DB="$H2/.config/hiiro/hiiro.db"; final_view; DB=$DB1; }
state "the restored database holds exactly the same records" "$FINAL" restored
check "restoring again keeps every row as identical" "${RESTORED//restored/identical}" restore_summary
/usr/bin/sqlite3 "$H2/.config/hiiro/hiiro.db" "update todos set text = 'edited after restore' where id = 7"
check "a conflicting later edit aborts the whole restore and keeps the edit" "Recovery rejected: Recovery conflicts with later write: todos/7
[exit 1]" in_home2 hb db restore "$SB/export.json"
state "the conflicting edit survives" "7|edited after restore" sh -c "/usr/bin/sqlite3 -separator '|' '$H2/.config/hiiro/hiiro.db' 'select id, text from todos where id = 7'"
