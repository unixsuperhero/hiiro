# 4b. Validation failure artifacts, clipboard/context bytes, file references,
# and recurring-job outcomes under a controlled clock with local jobs only.
source "$(dirname "$0")/lib.sh"
sandbox

# Controlled clock: every Ruby process sees 2026-10-13 12:00:00 UTC plus the
# real time elapsed since this scenario started, so occurrences are fixed and
# later processes never see an earlier time.
/bin/cat > "$SB/clock.rb" <<'RB'
module AcceptanceClock
  BASE = Time.utc(2026, 10, 13, 12, 0, 0)
  START = Float(ENV.fetch('CLOCK_START'))
  def now(**kw) = super(**kw) + (BASE.to_f - START)
end
Time.singleton_class.prepend(AcceptanceClock)
RB
ENVX=("TZ=UTC" "RUBYOPT=-r$SB/clock.rb" "CLOCK_START=$(/bin/date +%s)")
NORM=('s/run-2026101312[0-9]{4}-[0-9a-f]{8}/run-ID/g' 's/2026101312[0-9]{4}-[0-9a-f]{6}/RUN/g'
      's/2026-10-13T12:0([1-9]:[0-9]{2}|0:(0[1-9]|[1-5][0-9]))(\.[0-9]+)?(Z|00:00)/T/g' 's/\x1b\[[0-9;]*m//g' 's/2026101312[0-9]{4}/STAMP/g')

# The sandbox database is in WAL mode; a read-only sqlite3 open cannot create
# its shared-memory file, so these SELECT-only reads use a normal open.
rq() { /usr/bin/sqlite3 -separator '|' "$DB" "$@"; }

fixture pngpaste <<'SH'
#!/bin/sh
printf 'pngpaste\n' >> "$SB/tools.log"
[ -f "$SB/clip.png" ] && { cat "$SB/clip.png" > "$1"; exit 0; }
echo "No PNG data found on the clipboard!" >&2; exit 1
SH
fixture lint <<'SH'
#!/bin/sh
printf 'lint cwd=%s argv=%s\n' "$PWD" "$*" >> "$SB/lint.log"
echo "lint: 2 offenses"; echo "lint failing with 3" >&2
exit 3
SH
fixture check <<'SH'
#!/bin/sh
printf 'check cwd=%s argv=%s\n' "$PWD" "$*" >> "$SB/lint.log"
exit 0
SH

echo "== validation failure artifacts"
REPO_DIR="$SB/work/repo"
sx /bin/sh -c "mkdir -p '$REPO_DIR/app' && cd '$REPO_DIR' && git init -q -b main && git -c user.email=a@a -c user.name=a commit -q --allow-empty -m init && printf 'x\n' > 'app/a b.rb' && printf 'y\n' > app/-lead.rb"
/bin/mkdir -p "$H/.config/hiiro"
/bin/cat > "$H/.config/hiiro/tools.yml" <<'Y'
lint:
  tool_type: lint
  file_extensions: rb
  argv: [lint, '--', '[FILENAMES]']
check:
  tool_type: lint
  file_extensions: rb
  argv: [check, '[FILENAMES]']
Y

CWD="$REPO_DIR" check "h run lint: lint exits 3, check passes; the run exits 3 and keeps only the failed log" "$(cat <<'EOF'
dirty: 2 files under $SB/work/repo
==> lint: lint -- app/-lead.rb app/a\ b.rb
lint: 2 offenses
lint failing with 3
==> check: check app/-lead.rb app/a\ b.rb

--- run RUN: 1 failed, 1 succeeded
✗ lint   failed (exit 3)  log: $SB/home/.local/share/hiiro/captures/validation/RUN/01-lint.log
✓ check  exit 0
Queue these failures for an agent: h run queue RUN
[exit 3]
EOF
)" hexe h run lint
RUN=$(/bin/ls "$H/.local/share/hiiro/captures/validation" 2>/dev/null | /usr/bin/tail -1)

state "fixture tools got exact argv in the repository root" "$(cat <<'EOF'
lint cwd=$SB/work/repo argv=-- app/-lead.rb app/a b.rb
check cwd=$SB/work/repo argv=app/-lead.rb app/a b.rb
EOF
)" /bin/cat "$SB/lint.log"

state "retained logs: only the failed command's log, with its output" "$(cat <<'EOF'
01-lint.log
lint: 2 offenses
lint failing with 3
EOF
)" /bin/sh -c "ls '$H/.local/share/hiiro/captures/validation/$RUN'; cat '$H/.local/share/hiiro/captures/validation/$RUN/01-lint.log'"

state "a new process reads the failure record from the database" "$(cat <<'EOF'
lint|failed|3||validation|RUN|$SB/work/repo|{"task":null,"task_source":null,"app":null,"app_directory":null,"root":"$SB/work/repo","root_source":"git","directory":"$SB/work/repo","directory_source":"git"}
EOF
)" rq "select name, outcome, exit_status, exit_signal, source, run_id, cwd, context_json from captures order by id"

CWD="$REPO_DIR" check "h capture ls lists the failed validation in a later process" "$(cat <<'EOF'
   0. ✗  lint                    lint -- app/-lead.rb app/a\ b.rb
[exit 0]
EOF
)" hb capture ls

check "h run queue RUN writes one pending prompt and launches nothing" "$(cat <<'EOF'
Queued validation-RUN: $SB/home/.local/share/hiiro/queue/pending/validation-RUN.md
[exit 0]
EOF
)" hexe h run queue "$RUN"

state "the queue holds only that prompt, naming the run; no run records exist" "$(cat <<'EOF'
./pending/validation-RUN.md
---
validation_run: RUN
---
Validation run RUN has 1 failed command.
runs: 0
EOF
)" /bin/sh -c "cd '$H/.local/share/hiiro/queue' && find . -type f | sort; sed -n 1,4p pending/validation-$RUN.md; echo runs: \$(ls '$H/.local/share/hiiro/runs' 2>/dev/null | wc -l | tr -d ' ')"

echo "== clipboard and context bytes"
printf 'Meeting: Notes\r\nline two \xe2\x9c\x93\n\x00raw' > "$SB/clip.txt"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\xff\x00tail' > "$SB/clip.png"
/bin/cp "$SB/clip.txt" "$SB/clipboard.txt"

check "h save with an image on the clipboard saves the image first" "$(cat <<'EOF'
$SB/home/saved/STAMP-image.png
[exit 0]
EOF
)" hb save
IMG=$(/bin/ls "$H"/saved/*-image.png | /usr/bin/head -1)

state "the saved PNG is byte-identical to the clipboard image; only pngpaste was read" "$(cat <<EOF
$(sha "$SB/clip.png")
$(sha "$SB/clip.png")
pngpaste
EOF
)" /bin/sh -c "shasum -a 256 '$SB/clip.png' '$IMG' | cut -d' ' -f1; cat '$SB/tools.log'"

/bin/rm "$SB/clip.png"; : > "$SB/tools.log"
check "h save with only text keeps CRLF, UTF-8 and NUL bytes" "$(cat <<'EOF'
$SB/home/saved/STAMP-meeting-notes-line-two-raw.txt
[exit 0]
EOF
)" hb save
TXT=$(/bin/ls "$H"/saved/*-meeting-notes-line-two-raw.txt | /usr/bin/head -1)
state "text bytes identical (cmp) after pngpaste then pbpaste" "$(cat <<'EOF'
identical
pngpaste
pbpaste
EOF
)" /bin/sh -c "cmp -s '$SB/clip.txt' '$TXT' && echo identical; cat '$SB/tools.log'"

: > "$SB/tools.log"
save_typed() { hb save quick note; echo "[exit $?]"; echo "clipboard reads: $(/usr/bin/wc -l < "$SB/tools.log" | /usr/bin/tr -d ' ')"; /bin/cat "$H"/saved/*-quick-note.txt; echo; }
state "h save TEXT never reads the clipboard" "$(cat <<'EOF'
$SB/home/saved/STAMP-quick-note.txt
[exit 0]
clipboard reads: 0
quick note
EOF
)" save_typed

printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\xff\x00tail' > "$SB/clip.png"
check "h img save writes the clipboard image to the given path" "$(cat <<'EOF'
Saved to $SB/work/shot.png
[exit 0]
EOF
)" hb img save "$SB/work/shot.png"
state "h img save bytes identical; a second save refuses to replace it" "$(cat <<'EOF'
identical
EOF
)" /bin/sh -c "cmp -s '$SB/clip.png' '$SB/work/shot.png' && echo identical"
check "h img save over an existing file is refused without --force" "$(cat <<'EOF'
$SB/work/shot.png already exists (use --force to replace it)
[exit 1]
EOF
)" hb img save "$SB/work/shot.png"

CTXDAY=$(TZ=UTC /bin/date +%Y-%m-%d)
NORM+=("s#/notes/ctx/[0-9]{4}-[0-9]{2}-[0-9]{2}/#/notes/ctx/DAY/#g")
check "h context save NAME writes the clipboard text and appends it to the bundle" "$(cat <<'EOF'
$SB/home/notes/ctx/DAY/notes.md
attached to bundle $SB/home/notes/ctx/bundles/current.bundle
[exit 0]
EOF
)" hb context save notes.md
check "h context img NAME writes the clipboard image and appends it" "$(cat <<'EOF'
$SB/home/notes/ctx/DAY/diagram.png
attached to bundle $SB/home/notes/ctx/bundles/current.bundle
[exit 0]
EOF
)" hb context img diagram
state "context files byte-identical to the clipboard; manifest lists both" "$(cat <<'EOF'
identical
identical
$SB/home/notes/ctx/DAY/notes.md
$SB/home/notes/ctx/DAY/diagram.png
EOF
)" /bin/sh -c "d=\$(ls '$H/notes/ctx' | grep -v bundles); cmp -s '$SB/clip.txt' '$H/notes/ctx/'\$d/notes.md && echo identical; cmp -s '$SB/clip.png' '$H/notes/ctx/'\$d/diagram.png && echo identical; cat '$H/notes/ctx/bundles/current.bundle'"

echo "== task attachment and file references"
check "seed tasks alpha (waiting, next action review) and alpine" $'\n[exit 0]' sx ruby -e 'require "hiiro"; Hiiro::DB.setup!; Hiiro::TaskRecord.create(name: "alpha", status: "waiting", next_action: "review"); Hiiro::TaskRecord.create(name: "alpine", status: "active")'
TASKS_BEFORE=$(rq "select id, name, status, next_action, completed_at from tasks order by id")
: > "$SB/tools.log"
check "h save --task alpha --label shot reads only pngpaste and attaches once" "$(cat <<'EOF'
$SB/home/saved/STAMP-image.png
attached to task alpha
[exit 0]
EOF
)" hb save --task alpha --label shot
SHOT=$(rq "select target from task_resources where label = 'shot'")
check "t file add alpha on the same path keeps the one association" "$(cat <<'EOF'
1	file	shot	$SB/home/saved/STAMP-image.png
[exit 0]
EOF
)" hexe t file add alpha "$SHOT"
save_ambiguous() { : > "$SB/tools.log"; hb save --task alp; echo "[exit $?]"; echo "clipboard reads: $(/usr/bin/grep -c paste "$SB/tools.log")"; }
state "h save --task with an ambiguous prefix is refused before any clipboard read" "$(cat <<'EOF'
Ambiguous task alp: alpha, alpine
[exit 1]
clipboard reads: 0
EOF
)" save_ambiguous
file_ls() { hexe t file ls alpha; echo "[exit $?]"; rq "select id, name, status, next_action, completed_at from tasks order by id"; }
state "t file ls alpha in a new process lists one row; the task row is unchanged" "$(cat <<EOF
1	file	shot	\$SB/home/saved/STAMP-image.png
[exit 0]
$TASKS_BEFORE
EOF
)" file_ls
state "the attached file is the clipboard image, byte for byte" "identical" /bin/sh -c "cmp -s '$SB/clip.png' '$SHOT' && echo identical"

echo "== recurring jobs (manual runs of local definitions; nothing enabled)"
/bin/cat > "$H/.config/hiiro/schedules.yml" <<YML
report:
  job: command
  every: 1d
  command: [sh, -c, "echo building report; printf 'rows: 3\\\\n' > report.txt"]
  cwd: $SB/work
  artifacts: [report.txt]
broken:
  job: command
  every: 1d
  command: [sh, -c, "echo step one; echo 'fatal: cannot reach fixture db' >&2; exit 3"]
  cwd: $SB/work
slow:
  job: command
  every: 1d
  command: [sh, -c, "echo run >> $SB/slow.log; sleep 2"]
  cwd: $SB/work
reminders:
  job: reminders
  every: 1m
YML

check "h schedule ls lists the definitions, all off and never run" "$(cat <<'EOF'
report              command     every 86400s              off      never ran
broken              command     every 86400s              off      never ran
slow                command     every 86400s              off      never ran
reminders           reminders   every 60s                 off      never ran
[exit 0]
EOF
)" hb schedule ls

check "run report: completed, artifact recorded, occurrence is the clock's day slot" "$(cat <<'EOF'
report: 2026-10-13T00:00:00Z completed exit 0 (run-ID): exit 0
  artifact $SB/work/report.txt (8 bytes)
[exit 0]
EOF
)" hb schedule run report
check "run broken: failed exit 3, the log is kept" "$(cat <<'EOF'
broken: 2026-10-13T00:00:00Z failed exit 3 (run-ID): exit 3
  log $SB/home/.local/share/hiiro/jobs/broken/run-ID.log
[exit 1]
EOF
)" hb schedule run broken
state "the failed run's log holds its stdout and stderr" "$(cat <<'EOF'
step one
fatal: cannot reach fixture db
EOF
)" /bin/sh -c "cat '$H'/.local/share/hiiro/jobs/broken/*.log"
check "run report again: the completed occurrence is not run twice" "$(cat <<'EOF'
report: 2026-10-13T00:00:00Z already handled; nothing run
[exit 0]
EOF
)" hb schedule run report

two_workers() { hb schedule run slow > "$SB/w1.out" 2>&1 & hb schedule run slow > "$SB/w2.out" 2>&1 & wait; rq "select outcome from job_outcomes where definition='slow' order by outcome"; echo "executions: $(/usr/bin/wc -l < "$SB/slow.log" | /usr/bin/tr -d ' ')"; }
state "two concurrent workers for slow: one completes, one records skipped-overlap, one execution" "$(cat <<'EOF'
completed
skipped-overlap
executions: 1
EOF
)" two_workers

: > "$SB/tools.log"
check "h remind once saves a one-time reminder in the past (due)" "$(cat <<'EOF'
Saved one-time reminder #1: Submit timesheet (at 2026-01-01 12:00)
[exit 0]
EOF
)" hb remind once 'Submit timesheet' 202601011200 Glass
check "run reminders: delivers through the fixture notifier and completes" "$(cat <<'EOF'
reminders: 2026-10-13T12:00:00Z completed exit 0 (run-ID): exit 0
[exit 0]
EOF
)" hb schedule run reminders
state "exactly one notification with the reminder's message and sound" "$(cat <<'EOF'
terminal-notifier -message Submit timesheet -title Reminder -sound Glass
EOF
)" /bin/cat "$SB/tools.log"

check "a new process reads the outcomes newest first (no launchd query without a name)" "$(cat <<'EOF'
T  reminders         completed exit 0  exit 0
T  reminder:1        completed         delivered
T  slow              completed exit 0  exit 0
T  slow              skipped-overlap   occurrence held by run-ID
T  broken            failed exit 3     exit 3
    log $SB/home/.local/share/hiiro/jobs/broken/run-ID.log
T  report            completed exit 0  exit 0
    artifact $SB/work/report.txt (8 bytes)
[exit 0]
EOF
)" hb schedule status

state "job_outcomes rows and checkpoints after reload" "$(cat <<'EOF'
report|2026-10-13T00:00:00Z|1|completed|0|[{"path":"$SB/work/report.txt","bytes":8}]
broken|2026-10-13T00:00:00Z|1|failed|3|[]
slow|2026-10-13T00:00:00Z||skipped-overlap||
slow|2026-10-13T00:00:00Z|1|completed|0|[]
reminder:1|2026-01-01T12:00:00+00:00|1|completed||
reminders|2026-10-13T12:00:00Z|1|completed|0|[]
--
broken|0|2026-10-13T00:00:00Z|failed
reminders|0|2026-10-13T12:00:00Z|completed
report|0|2026-10-13T00:00:00Z|completed
slow|0|2026-10-13T00:00:00Z|completed
EOF
)" /bin/sh -c "sqlite3 -separator '|' '$DB' \"select definition, occurrence, attempt, outcome, exit_code, artifacts_json from job_outcomes order by id\"; echo --; sqlite3 -separator '|' '$DB' \"select definition, enabled, last_due, last_outcome from schedule_checkpoints order by definition\""

state "no producer-written dashboard or status file; launchctl was never called; nothing in LaunchAgents" "$(cat <<'EOF'
dashboards: 0
launchctl calls: 0
LaunchAgents: absent
EOF
)" /bin/sh -c "echo dashboards: \$(find '$H' \( -name status.json -o -name info.json -o -name '*.html' \) | wc -l | tr -d ' '); echo launchctl calls: \$(grep -c launchctl '$SB/tools.log'); [ -e '$H/Library/LaunchAgents' ] && echo LaunchAgents: present || echo LaunchAgents: absent"
