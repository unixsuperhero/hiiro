# 3. Task and directory context: t, tt, and h task over explicit selection,
# directory inference, calling-pane identity, ambiguity, and no task; path and
# execution cwd agree; read-only discovery writes nothing. Existing
# directories and recorded tree references only; no worktree is created.
source "$(dirname "$0")/lib.sh"
sandbox

# A WAL database without -shm cannot be opened read-only; immutable reads the
# committed file without creating anything.
qi() { /usr/bin/sqlite3 -separator '|' "file:$DB?immutable=1" "$@"; }
G=(/usr/bin/git -c user.email=t@example.com -c user.name=t -c init.defaultBranch=main)
for repo in repo-a repo-b; do
  /bin/mkdir -p "$SB/$repo/apps/web/src" "$SB/$repo/lib"
  echo x > "$SB/$repo/README"
  "${G[@]}" -C "$SB/$repo" init -q && "${G[@]}" -C "$SB/$repo" add . && "${G[@]}" -C "$SB/$repo" commit -q -m init
done
"${G[@]}" -C "$SB/repo-b" checkout -q -b feature-b
fixture cwdlog <<'SH'
#!/bin/sh
printf '%s\n' "$PWD" >> "$SB/cwd.log"
SH

# within DIR CMD... [-- CMD...]: run each command in DIR, stopping at the first failure.
within() {
  local dir=$1 seg=() arg; shift
  for arg in "$@" --; do
    if [ "$arg" = -- ]; then CWD=$dir "${seg[@]}" || return $?; seg=(); else seg+=("$arg"); fi
  done
}
seed() {
  hexe t new alpha && hexe t new alpine && hexe t directory add alpha "$SB/repo-a" --primary &&
    sx ruby -e "require 'hiiro'; Hiiro::DB.setup!; Hiiro::TaskRecord.create(name: 'beta', tree: '$SB/repo-b', session: 'beta'); puts 'beta recorded'" &&
    hb app add web apps/web
}
pin_then_current() { hexe t use beta && hexe t current && CWD="$SB/repo-a" hexe t current; }
listing() { (cd "$H" && /usr/bin/find . | LC_ALL=C /usr/bin/sort); }
refs() { local repo; for repo in repo-a repo-b; do "${G[@]}" -C "$SB/$repo" for-each-ref --format='%(refname) %(objectname:short)'; "${G[@]}" -C "$SB/$repo" config --get-regexp '^branch\.' ; done; }
exits() { local spec; for spec in "$@"; do (eval "CWD=$SB/repo-a sx ruby $REPO/exe/$spec" > /dev/null 2>&1); printf '%s -> %s\n' "$spec" "$?"; done; }

# --- read-only discovery and help in a fresh sandbox
before_home=$(listing)
before_refs=$(refs)
check "root, task, and nested help/discovery exit as documented (help without a subcommand exits 1)" "$(cat <<'EOF'
h -> 1
h --help -> 1
h bin list -> 0
h bin complete -> 0
h queue -> 1
h task --help -> 1
t --help -> 1
t help -> 1
t todo --help -> 1
tt --help -> 1
[exit 0]
EOF
)" exits 'h' 'h --help' 'h bin list' 'h bin complete' 'h queue' 'h task --help' 't --help' 't help' 't todo --help' 'tt --help'

state "discovery created no database, plugin dir, or other file under HOME" "$before_home" listing
state "discovery left refs and branch config of both repositories unchanged (no branch tags)" "$before_refs" refs

# --- records: alpha (primary directory repo-a), alpine (no directory), beta (absolute tree repo-b), app web
check "tasks and an app are created through the CLI and a recorded tree reference" "$(cat <<'EOF'
Created alpha
$SB/home/notes/work/alpha
Created alpine
$SB/home/notes/work/alpine
1	directory	$SB/repo-a
beta recorded
Added app 'web' => apps/web
[exit 0]
EOF
)" seed

state "stored task rows keep the primary directory and the absolute tree reference" "$(cat <<'EOF'
alpha||$SB/repo-a
alpine||
beta|$SB/repo-b|
EOF
)" qi "select name, tree, primary_directory from tasks order by name"

check "t ls lists the three tasks" "$(cat <<'EOF'
alpha   active
alpine  active
beta    active
[exit 0]
EOF
)" hexe t ls

# --- explicit task/app selection; t, tt, and h task agree
check "t path alpha (explicit task)" "$(printf '%s\n[exit 0]' '$SB/repo-a')" hexe t path alpha
check "h task path alpha gives the same directory" "$(printf '%s\n[exit 0]' '$SB/repo-a')" hexe h task path alpha
check "t abspath alph (unique prefix) gives the same directory" "$(printf '%s\n[exit 0]' '$SB/repo-a')" hexe t abspath alph
check "t path alpha web (positional app)" "$(printf '%s\n[exit 0]' '$SB/repo-a/apps/web')" hexe t path alpha web
check "h task path alpha --app web (flag app) gives the same directory" "$(printf '%s\n[exit 0]' '$SB/repo-a/apps/web')" hexe h task path alpha --app web
check "t path alpha nope (missing app) fails" "$(printf '%s\n[exit 1]' 'ERROR: App not found: nope')" hexe t path alpha nope
check "tt add alpha writes a todo" "$(printf '%s\n[exit 0]' 'Added todo 1 to alpha: write tests')" hexe tt add alpha write tests
check "t todo ls alpha, tt ls alpha, and h task todo ls alpha print the same todo" "$(cat <<'EOF'
Todo 1 [not_started]: write tests
Todo 1 [not_started]: write tests
Todo 1 [not_started]: write tests
[exit 0]
EOF
)" within "$SB/work" hexe t todo ls alpha -- hexe tt ls alpha -- hexe h task todo ls alpha

# --- directory inference from nested directories
check "t current inside repo-a/apps/web/src infers alpha by primary directory" "$(printf '%s\n[exit 0]' alpha)" within "$SB/repo-a/apps/web/src" hexe t current
check "h task current there infers the same task" "$(printf '%s\n[exit 0]' alpha)" within "$SB/repo-a/apps/web/src" hexe h task current
check "t current and t path inside repo-b/lib infer beta by its tree" "$(printf '%s\n%s\n%s\n[exit 0]' beta '$SB/repo-b' feature-b)" within "$SB/repo-b/lib" hexe t current -- hexe t path -- hexe t branch

# --- ambiguity and no task (off a terminal: errors, no chooser)
check "t path al (alpha, alpine) off a terminal is an error, not a chooser" "$(printf '%s\n[exit 1]' 'ERROR: Ambiguous task al: alpha, alpine')" hexe t path al
check "tt ls al is the same error" "$(printf '%s\n[exit 1]' 'ERROR: Ambiguous task al: alpha, alpine')" hexe tt ls al
check "t current outside every task directory with no pin fails" "$(printf '%s\n[exit 1]' 'ERROR: No current task; supply a task name or run t use NAME')" hexe t current
check "h task path outside every task directory fails the same way" "$(printf '%s\n[exit 1]' 'ERROR: No current task; supply a task name or run t use NAME')" hexe h task path

# --- calling-pane identity (no herdr on PATH, no server)
ENVX=(HERDR_ENV=1 HERDR_WORKSPACE_ID=w9 HERDR_TAB_ID=w9:t1 HERDR_PANE_ID=w9:p1)
check "with calling IDs but no Herdr server, inference refuses instead of falling back to the directory" "$(printf '%s\n[exit 1]' 'ERROR: Herdr is not running; start Herdr for workspace/tab/pane commands')" within "$SB/repo-a" hexe t current
check "an explicit task still answers under those IDs" "$(printf '%s\n%s\n[exit 0]' alpha '$SB/repo-a')" within "$SB/work" hexe t current alpha -- hexe t path alpha
check "t cd alpha cannot validate the calling pane and sends nothing" "$(printf '%s\n[exit 1]' 'ERROR: Herdr is not running; start Herdr for workspace/tab/pane commands, or supply a task name for task data')" hexe t cd alpha
ENVX=(HERDR_ENV=1)
check "a Herdr context without calling IDs is an error, even inside repo-a" "$(printf '%s\n[exit 1]' 'ERROR: Missing calling Herdr workspace/pane IDs; supply a task name')" within "$SB/repo-a" hexe t current
ENVX=()

# --- pin fallback: used only where no directory identifies a task
check "t use beta, then t current outside (pin) and inside repo-a (directory wins)" "$(printf '%s\n%s\n%s\n[exit 0]' beta beta alpha)" pin_then_current

# --- path output and execution cwd agree
/bin/mkdir -p "$H/.config/hiiro"
printf 'cwdlog:\n  tool_type: lint\n  argv: [cwdlog]\n' > "$H/.config/hiiro/tools.yml"
run_cwds() {
  /bin/rm -f "$SB/cwd.log"
  hexe t sh alpha cwdlog > /dev/null 2>&1
  hexe t run alpha all > /dev/null 2>&1
  hexe t run alpha --app web all > /dev/null 2>&1
  CWD="$SB/repo-b/lib" hexe h run all > /dev/null 2>&1
  CWD="$SB/repo-b/lib" hexe t sh cwdlog > /dev/null 2>&1
  /bin/cat "$SB/cwd.log"
}
state "t sh, t run, t run --app, and inferred h run / t sh (from repo-b/lib) execute where t path points (the task root)" "$(cat <<'EOF'
$SB/repo-a
$SB/repo-a
$SB/repo-a/apps/web
$SB/repo-b
$SB/repo-b
EOF
)" run_cwds

final_rows() { qi 'select name, tree, primary_directory from tasks order by name'; qi 'select task_id, kind, target from task_resources'; qi 'select task_name, text, status from todos'; qi "select resource_type, name, value from registry where resource_type = 't'"; }
# --- nothing created a worktree or changed refs; one invocation per command was recorded
state "both repositories still list exactly one worktree" "$(cat <<'EOF'
$SB/repo-a
$SB/repo-b
EOF
)" /bin/bash -c "for r in repo-a repo-b; do /usr/bin/git -C $SB/\$r worktree list --porcelain | /usr/bin/sed -n 's/^worktree //p'; done"
state "refs and branch config unchanged by every command above" "$before_refs" refs
state "task rows unchanged; alpha's resource, the todo, and the t use pin (beta = task id 3, in table t) are stored" "$(cat <<'EOF'
alpha||$SB/repo-a
alpine||
beta|$SB/repo-b|
1|directory|$SB/repo-a
alpha|write tests|not_started
t|current_task|3
EOF
)" final_rows
