# 4a. Owned execution: foreground capture and validation, queue (current and
# detached tick), service start/status/stop, and background runs, with real
# harmless children. Run records must tell a finished child from a running
# one, and a stop must never signal a process the run does not own.
source "$(dirname "$0")/lib.sh"
sandbox
ENVX=(SHELL=/bin/bash)
NORM=('s/run-[0-9]{14}-[0-9a-f]{8}/RUN/g' 's/[0-9]{14}-[0-9a-f]{6}/VRUN/g' 's/pid [0-9]+/pid PID/g'
      's/[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}/MM-DD HH:MM/g' 's/web@[0-9a-f]{8}/web@KEY/g' 's/Process [0-9]+ for/Process PID for/')
RUNS="$H/.local/share/hiiro/runs"
QUEUE="$H/.local/share/hiiro/queue"
OWN=()      # pids this scenario started outside hiiro
cleanup() {
  local pid
  for pid in ${OWN[@]+"${OWN[@]}"}; do kill -KILL "$pid" 2>/dev/null; done
  # service children recorded in sandbox run records (owned by this scenario)
  [ -d "$RUNS" ] && for pid in $(/usr/bin/grep -hoE '"pid": *[0-9]+' "$RUNS"/*.json 2>/dev/null | /usr/bin/grep -oE '[0-9]+$'); do
    /bin/ps -o command= -p "$pid" 2>/dev/null | /usr/bin/grep -q "$SB" && kill -KILL "$pid" 2>/dev/null
  done
  return 0
}
trap cleanup EXIT

# id owner-name state outcome placement, one line per run record of an owner kind
runs() {
  sx ruby -rjson -e '
    # Allocation order: the record file is created at allocation and its birth time has
    # sub-second precision, unlike times.allocated (whole seconds, so two launches tie).
    Dir[File.join(ARGV[0], "*.json")].map { |f| [File.birthtime(f), JSON.parse(File.read(f))] }.select { |_, r| r["owner"]["kind"] == ARGV[1] }
      .sort_by { |born, r| [born, r["owner"]["name"].to_s] }.map(&:last)
      .each { |r| o = r["outcome"]; puts [r["owner"]["name"] || r["owner"]["instance"] || "-", r["state"], o ? (o["signal"] ? "signal #{o["signal"]}" : "exit #{o["exit_code"]}") : "running", r["placement"]["kind"], r["error"] ? "error: #{r["error"]}" : nil].compact.join("  ") }' "$RUNS" "$1"
}
# A detached launch must not keep the caller's stdout: report whether a pipe on
# the command's output reaches EOF within 15 s of the command returning.
pipe_returns() {
  sx "$@" 2>&1 | /usr/bin/perl -e '$SIG{ALRM} = sub { print "pipe still open 15s after the command\n"; exit 0 }; alarm 15; print while <STDIN>; print "pipe closed\n"'
}
# Output through a file, so a leaked descriptor cannot block the scenario.
to_file() { "$@" > "$SB/cmd.out" 2>&1; local code=$?; /bin/cat "$SB/cmd.out"; echo "[exit $code]"; }
# sorted "SORT_KEYS" CMD...: listing order within one second is unspecified
sorted() { local keys=$1; shift; "$@" | LC_ALL=C /usr/bin/sort $keys; }
wait_for() { local i; for i in $(seq 1 150); do eval "$1" && return 0; /bin/sleep 0.1; done; return 1; }

fixture omp <<'SH'
#!/bin/sh
# Fixture agent: prints the prompt it was handed, exits OMP_EXIT.
for a in "$@"; do case "$a" in @*) printf 'agent read: %s\n' "$(cat "${a#@}")";; esac; done
exit "${OMP_EXIT:-0}"
SH
fixture lint <<'SH'
#!/bin/sh
echo "lint saw: $*"
exit 3
SH

# --- foreground: binary stdin through h capture, child exit status kept
/usr/bin/printf 'head\000\377\376bytes\r\nend' > "$SB/input.bin"
IN_SHA=$(sha "$SB/input.bin")
capture_bytes() {
  sx ruby "$REPO/bin/h-capture" file bytes.bin /bin/sh -c 'cat; exit 7' < "$SB/input.bin" > "$SB/terminal.bin" 2> "$SB/capture.err"
  echo "cli exit $?"
  cat "$SB/capture.err"
  [ "$(sha "$SB/terminal.bin")" = "$IN_SHA" ] && echo "terminal bytes == stdin bytes"
  [ "$(sha "$H/.local/share/hiiro/captures/bytes.bin")" = "$IN_SHA" ] && echo "saved bytes == stdin bytes"
  q "select name, exit_status, outcome, source from captures"
}
state "h capture streams stdin bytes to the terminal and the file and exits with the child's 7" "$(cat <<'EOF'
cli exit 7

[capture saved: $SB/home/.local/share/hiiro/captures/bytes.bin (exit 7)]
terminal bytes == stdin bytes
saved bytes == stdin bytes
bytes.bin|7|failed|capture
EOF
)" capture_bytes

check "h capture of a command that cannot start exits 127" "$(cat <<'EOF'
/nonexistent/tool: No such file or directory - /nonexistent/tool

[capture saved: $SB/home/.local/share/hiiro/captures/nostart.log (exit 127)]
[exit 127]
EOF
)" hb capture file nostart.log /nonexistent/tool

run_in_repo() { CWD="$SB/repo" hexe h run; }
# --- foreground validation: a failing recipe keeps its log and exit status
/bin/mkdir -p "$SB/repo/.git-init" && /bin/rmdir "$SB/repo/.git-init"
CWD="$SB/repo" sx /usr/bin/git init -q -b main . >/dev/null
echo 'x = 1' > "$SB/repo/a.rb"
/bin/mkdir -p "$H/.config/hiiro"
cat > "$H/.config/hiiro/tools.yml" <<'YML'
lint:
  tool_type: lint
  file_extensions: rb
  argv: [lint, "[FILENAMES]"]
YML
check "h run streams the failing tool's output and exits with its 3" "$(cat <<'EOF'
dirty: 1 file under $SB/repo
==> lint: lint a.rb
lint saw: a.rb

--- run VRUN: 1 failed
✗ lint  failed (exit 3)  log: $SB/home/.local/share/hiiro/captures/validation/VRUN/01-lint.log
Queue these failures for an agent: h run queue VRUN
[exit 3]
EOF
)" run_in_repo

# --- queue in the current terminal: exit 0, exit 5, and an agent that cannot start
check "h queue cadd runs the agent in the foreground and exits 0" "$(cat <<'EOF'
agent read: Say ok
[exit 0]
EOF
)" hexe h queue cadd -n ok-run 'Say ok'

ENVX=(SHELL=/bin/bash OMP_EXIT=5)
check "h queue cadd passes the agent's exit 5 through" "$(cat <<'EOF'
agent read: Say five
[exit 5]
EOF
)" hexe h queue cadd -n five-run 'Say five'
ENVX=(SHELL=/bin/bash)

/bin/mv "$SB/fix/omp" "$SB/omp.off"
check "h queue cadd with no agent on PATH fails to start with 127" "$(cat <<'EOF'
[RUN] not started: omp @$SB/home/.local/share/hiiro/queue/running/nostart.prompt: No such file or directory - omp
[exit 127]
EOF
)" hexe h queue cadd -n nostart 'Cannot start'
/bin/mv "$SB/omp.off" "$SB/fix/omp"

state "queue entries settle by observed outcome" "$(cat <<'EOF'
done/ok-run.md
done/ok-run.meta
failed/five-run.md
failed/five-run.meta
failed/nostart.md
failed/nostart.meta
EOF
)" /bin/sh -c "cd '$QUEUE' && /usr/bin/find . -type f | /usr/bin/sed 's#^\./##' | LC_ALL=C /usr/bin/sort"

# --- queue detached through tick: a long-lived agent is running, then completes
ENVX=(SHELL=/bin/bash OMP_EXIT=0)
fixture omp <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in @*) printf 'agent read: %s\n' "$(cat "${a#@}")";; esac; done
while [ ! -f "$SB/release-agent" ]; do sleep 0.1; done
exit "${OMP_EXIT:-0}"
SH
ticked_running() { runs queue | /usr/bin/grep ticked; hexe h queue tick --max 1; }
hexe h queue add -n ticked 'Tick me' >/dev/null
check "h queue tick launches the oldest pending entry detached" "$(cat <<'EOF'
Launched: ticked [RUN started pid PID]
tick: launched 1, running 1 of 1
[exit 0]
EOF
)" hexe h queue tick --max 1
wait_for "[ -f '$QUEUE/running/ticked.log' ] && /usr/bin/grep -q 'agent read' '$QUEUE/running/ticked.log'"
state "while the agent runs its run record is active and a second tick launches nothing" "$(cat <<'EOF'
ticked  started  running  detached
tick: launched 0, running 1 of 1
EOF
)" ticked_running
touch "$SB/release-agent"
ticked_done() { cat "$QUEUE/done/ticked.log"; runs queue; }
wait_for "[ -f '$QUEUE/done/ticked.md' ]"
state "after the agent exits the entry and its log move to done/ and the record is completed" "$(cat <<'EOF'
agent read: Tick me
ok-run  completed  exit 0  current
five-run  failed  exit 5  current
nostart  failed  running  current  error: omp @$SB/home/.local/share/hiiro/queue/running/nostart.prompt: No such file or directory - omp
ticked  completed  exit 0  detached
EOF
)" ticked_done

# --- service: detached long-lived child, status, explicit stop, unrelated pid
/bin/mkdir -p "$SB/svc/alpha"
cat > "$H/.config/hiiro/services.yml" <<YML
web:
  base_dir: $SB/svc/alpha
  start: exec ruby -e 'trap("TERM") { File.write("term-received", "yes"); exit 0 }; File.write("pid", Process.pid.to_s); sleep'
  ready: test -f pid
  cleanup:
    - pwd > cleaned
YML
check "h service start launches detached, waits for readiness, and releases the caller's stdout" "$(cat <<'EOF'
Started service 'web' as web@KEY (started pid PID)
pipe closed
[exit 0]
EOF
)" pipe_returns ruby "$REPO/exe/h" service start web
wait_for "[ -f '$SB/svc/alpha/pid' ]"
SVC_PID=$(cat "$SB/svc/alpha/pid")
svc_ls_runs() { hexe h service ls; runs service; }
state "a second start of the same instance is refused" "$(cat <<'EOF'
Service 'web' is already running as web@KEY (ready pid PID)
[exit 1]
EOF
)" to_file hexe h service start web
state "a new process lists the instance as ready from its run record" "$(cat <<'EOF'
Services:

  web                   🟢
    web@KEY              ready pid PID  $SB/svc/alpha
web@KEY  ready  running  detached
EOF
)" svc_ls_runs

# An unrelated process the run does not own: put its pid in the run record.
/bin/sleep 300 &
UNRELATED=$!
OWN+=("$UNRELATED")
SVC_RUN=$(/usr/bin/grep -lE '"kind": *"service"' "$RUNS"/*.json | head -1)
/bin/cp "$SVC_RUN" "$SB/svc-run.json.orig"
sx ruby -rjson -e 'r = JSON.parse(File.read(ARGV[0])); r["process"]["pid"] = Integer(ARGV[1]); File.write(ARGV[0], JSON.generate(r))' "$SVC_RUN" "$UNRELATED"
check "stop refuses to signal a pid whose start time is not the recorded one" "$(cat <<'EOF'
Process PID for 'web@KEY' is gone or was reused; not signalling it
Stopped service 'web@KEY' (failed: exited without a recorded status)
[exit 0]
EOF
)" hexe h service stop web
state "the unrelated process survived; the real service child was not signalled either" "$(cat <<EOF
unrelated alive
service child alive
term-received absent
EOF
)" /bin/sh -c "kill -0 $UNRELATED 2>/dev/null && echo 'unrelated alive'; kill -0 $SVC_PID 2>/dev/null && echo 'service child alive'; [ -f '$SB/svc/alpha/term-received' ] && echo term-received present || echo term-received absent"
kill -KILL "$UNRELATED" 2>/dev/null; wait "$UNRELATED" 2>/dev/null
kill -TERM "$SVC_PID" 2>/dev/null
wait_for "! kill -0 $SVC_PID 2>/dev/null"
/bin/rm -f "$SB/svc/alpha/pid" "$SB/svc/alpha/term-received" "$SB/svc/alpha/cleaned"

start_stop() { to_file hexe h service start web; to_file hexe h service stop web; }
state "a fresh start then an explicit stop signals the owned child and records its exit" "$(cat <<'EOF'
Started service 'web' as web@KEY (started pid PID)
[exit 0]
Stopped service 'web@KEY' (completed exit 0)
[exit 0]
EOF
)" start_stop
after_stop() { echo "term-received $(cat "$SB/svc/alpha/term-received")"; echo "cleaned $(cat "$SB/svc/alpha/cleaned")"; hexe h service ls; }
state "the owned child received TERM, cleanup ran in its directory, and ls shows nothing running" "$(cat <<'EOF'
term-received yes
cleaned $SB/svc/alpha
Services:

  web                   🔴
EOF
)" after_stop
check "stopping a service that is not running signals nothing" "$(cat <<'EOF'
Service 'web' is not running
[exit 1]
EOF
)" hexe h service stop web

# --- background: detached normal exit, failure, and a long-lived child
check "h bg run (no multiplexer) launches detached and reports the failed exit" "$(cat <<'EOF'
RUN failed exit 4 [detached]
[exit 0]
EOF
)" hb bg run sh -c 'exit 4'
check "h bg run of a long-lived child returns once it has started" "$(cat <<'EOF'
RUN started pid PID [detached]
pipe closed
[exit 0]
EOF
)" pipe_returns ruby "$REPO/bin/h-bg" run sh -c 'while [ ! -f release-bg ]; do sleep 0.1; done; echo done > bg-out'
state "a new process sees the long-lived run as started, the failed one as failed" "$(cat <<'EOF'
-  failed  exit 4  detached
-  started  running  detached
EOF
)" sorted "" runs background
touch "$SB/work/release-bg"
wait_for "[ -f '$SB/work/bg-out' ]"
wait_for "runs background | /usr/bin/grep -q completed"
state "after reload h bg ls distinguishes completed from failed" "$(cat <<'EOF'
RUN  completed exit 0  /bin/bash -lc sh\ -c\ while\\\ \\\[\\\ \\\!\\\ -f\\\ release-bg\\\ \\\]\\\;\\\ do\\\ sleep\\\ 0.1\\\;\\\ done\\\;\\\ echo\\\ done\\\ \\\>\\\ bg-out
RUN  failed exit 4  /bin/bash -lc sh\ -c\ exit\\\ 4
EOF
)" sorted "-k2,2" hb bg ls

# --- reload: status from records only, no producer-written dashboard
state "a new process lists queue entries with their recorded outcomes" "$(cat <<'EOF'
done       MM-DD HH:MM  ok-run  (0m)  {completed exit 0}  | Say ok
done       MM-DD HH:MM  ticked  (0m)  {completed exit 0}  | Tick me
failed     MM-DD HH:MM  five-run  (0m)  {failed exit 5}  | Say five
failed     MM-DD HH:MM  nostart  (0m)  {failed: omp @$SB/home/.local/share/hiiro/queue/running/nostart.prompt: No such file or directory - omp}  | Cannot start
EOF
)" sorted "-k1,1 -k4,4" hexe h queue ls
state "producers wrote no status/dashboard file; runtime holds only runs, queue, and captures" "$(cat <<'EOF'
captures
queue
runs
EOF
)" /bin/sh -c "/bin/ls '$H/.local/share/hiiro'; /usr/bin/find '$H' \\( -name 'status.json' -o -name 'info.json' -o -name '*.html' -o -name 'dashboard*' \\) -print"
state "no child started by this scenario is still running" "" /bin/sh -c "/bin/ps -A -o pid=,command= | /usr/bin/grep -F '$SB' | /usr/bin/grep -v -e grep -e 'ps -A' -e '/bin/sh -c' -e /usr/bin/sed || true"
