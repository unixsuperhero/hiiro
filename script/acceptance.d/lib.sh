# Shared helpers for script/acceptance scenarios. Sourced by bash only.
#
#   sandbox [NAME]            fresh $SB with home/, fix/ (fixtures), work/, gem-home/, tmp/
#   sx CMD...                 run CMD under `env -i` with the sandbox environment, in $CWD
#                             (default $SB/work), killed with its process group after
#                             ${LIMIT:-120} s; ENVX=(K=V ...) adds variables
#   hb BIN ARGS / hexe EXE ARGS   a checkout bin/h-BIN or exe/EXE through sx
#   check LABEL EXPECTED CMD...   print EXPECTED, run CMD, compare its stdout+stderr
#                             followed by "[exit N]" (sandbox paths shown as $SB)
#   state LABEL EXPECTED CMD...   the same, without the exit line (state queries)
#   want <<'EOF' ... EOF       read an expected text into $WANT (bash 3.2 misparses
#                             quotes in a heredoc inside "$(...)")
#   incomplete LABEL REASON   a check that could not run
#   q SQL                     query the sandbox database with query_only set (a WAL
#                             database cannot be opened -readonly before its -shm exists)
set -u
[ -n "${BASH_VERSION:-}" ] || { echo "lib.sh needs bash" >&2; exit 2; }
RUBY=${HIIRO_ACCEPTANCE_RUBY:-/Volumes/yaba/homedir/.rbenv/versions/3.3.10/bin/ruby}
GEMS=${HIIRO_ACCEPTANCE_GEMS:-/private/tmp/rehiiro-step01.pLzQwX/gems/ruby/3.3.0}
CHECK=0
ENVX=()
NORM=()

sandbox() {
  SB="$OUT/sb/$SCENARIO${1:+-$1}"
  /bin/rm -rf "$SB"
  /bin/mkdir -p "$SB"/{home,fix,rubybin,work,gem-home,tmp}
  SB=$(cd "$SB" && pwd -P)
  H="$SB/home"
  DB="$H/.config/hiiro/hiiro.db"
  /bin/ln -s "$RUBY" "$SB/rubybin/ruby"
  SBPATH="$SB/fix:$SB/rubybin:$REPO/bin:/usr/bin:/bin"
  fixture editor <<'SH'
#!/bin/sh
# Records each edited file; EDIT_SCRIPT (if set) rewrites it.
printf '%s\n' "$*" >> "$SB/editor.log"
[ -n "${EDIT_SCRIPT:-}" ] && exec /bin/sh "$EDIT_SCRIPT" "$@"
exit 0
SH
  # The live clipboard, opener, notifier, speech, AppleScript, and launchd
  # are shadowed by recorders; a scenario overrides one with its own fixture.
  local tool
  for tool in pbcopy open osascript say terminal-notifier launchctl; do
    fixture "$tool" <<'SH'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$SB/tools.log"
[ "$(basename "$0")" = pbcopy ] && cat > "$SB/clipboard.out"
exit 0
SH
  done
  fixture pbpaste <<'SH'
#!/bin/sh
printf 'pbpaste\n' >> "$SB/tools.log"
[ -f "$SB/clipboard.txt" ] && cat "$SB/clipboard.txt"
exit 0
SH
  /bin/cat > "$SB/limit" <<'PL'
#!/usr/bin/perl
# limit SECONDS CMD...: run CMD in its own process group; kill the group on timeout.
my $t = shift;
my $pid = fork;
if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
$SIG{ALRM} = sub { kill 'KILL', -$pid; print STDERR "[killed after ${t}s]\n" };
$SIG{INT} = sub { kill 'INT', -$pid };
alarm $t;
waitpid($pid, 0);
my $s = $?;
alarm 0;
kill 'KILL', -$pid;
exit($s & 127 ? 128 + ($s & 127) : $s >> 8);
PL
  /bin/chmod +x "$SB/limit"
  echo "sandbox: $SB"
}

fixture() { /bin/cat > "$SB/fix/$1"; /bin/chmod +x "$SB/fix/$1"; }

senv() {
  printf '%s\n' "HOME=$H" "USER=accept" "LOGNAME=accept" "LANG=en_US.UTF-8" "TERM=dumb" "SB=$SB" \
    "PATH=$SBPATH" "RUBYLIB=$REPO/lib" "GEM_HOME=$SB/gem-home" "GEM_PATH=$GEMS" "TMPDIR=$SB/tmp" \
    "EDITOR=$SB/fix/editor" "VISUAL=$SB/fix/editor" ${ENVX[@]+"${ENVX[@]}"}
}

sx() {
  local env=()
  while IFS= read -r line; do env+=("$line"); done < <(senv)
  (cd "${CWD:-$SB/work}" && /usr/bin/env -i "${env[@]}" "$SB/limit" "${LIMIT:-120}" "$@")
}
hb() { local bin=$1; shift; sx ruby "$REPO/bin/h-$bin" "$@"; }
hexe() { local exe=$1; shift; sx ruby "$REPO/exe/$exe" "$@"; }

norm() {
  local args=(-e "s#$SB#\$SB#g")
  local expr
  for expr in ${NORM[@]+"${NORM[@]}"}; do args+=(-e "$expr"); done
  LANG=en_US.UTF-8 /usr/bin/sed -E "${args[@]}"
}

_record() {
  local want=$1 got=$2 result
  [ "$got" = "$want" ] && result=pass || result=FAIL
  printf 'observed:\n%s\nresult: %s\n' "$got" "$result"
  printf '%s\t%s\t%s\n' "$SCENARIO.$CHECK" "$result" "$LABEL" >> "$OUT/results.tsv"
}

_expect() {
  CHECK=$((CHECK + 1))
  LABEL=$1
  printf '\n--- [%s.%d] %s\nexpected:\n%s\n' "$SCENARIO" "$CHECK" "$LABEL" "$2"
}

check() {
  local want=$2 out code
  _expect "$1" "$want"
  shift 2
  out=$("$@" 2>&1)
  code=$?
  _record "$want" "$(printf '%s\n[exit %s]' "$out" "$code" | norm)"
}

state() {
  local want=$2
  _expect "$1" "$want"
  shift 2
  _record "$want" "$("$@" 2>&1 | norm)"
}

want() { WANT=$(/bin/cat); }

incomplete() {
  CHECK=$((CHECK + 1))
  printf '\n--- [%s.%d] %s\nincomplete: %s\n' "$SCENARIO" "$CHECK" "$1" "$2"
  printf '%s\t%s\t%s\n' "$SCENARIO.$CHECK" "incomplete" "$1: $2" >> "$OUT/results.tsv"
}

q() { /usr/bin/sqlite3 -cmd 'PRAGMA query_only=1' -separator '|' "$DB" "$@"; }
sha() { /usr/bin/shasum -a 256 "$@" | /usr/bin/awk '{ print $1 }'; }
resolves() { local name; for name in "$@"; do printf '%s -> %s\n' "$name" "$(PATH=$SBPATH command -v "$name" || echo none)"; done; }
