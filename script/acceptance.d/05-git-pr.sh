# 5. Git commit planning that never touches the index, and repository-qualified
# PR snapshots, actions, and monitoring through the controlled gh adapter
# (test/support/fake_gh.rb). Adapter-limited: no live GitHub call is made.
source "$(dirname "$0")/lib.sh"
ENVX=(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
      GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid)
NORM=('s/^Last updated: .*/Last updated: TIME/' 's/fetched [0-9T:.Z-]+/fetched TIME/g')

# ---------------------------------------------------------------- (a) commit planning
sandbox git
R="$SB/work/repo"
fixture claude <<'SH'
#!/bin/sh
# Controlled planner: records argv and prompt, prints $SB/plan.json.
cat > "$SB/planner-prompt.txt"
printf '%s\n' "$*" >> "$SB/planner-argv.log"
cat "$SB/plan.json"
SH

make_repo() {
  /bin/mkdir -p "$R" && cd "$R" || return 1
  git init -q -b main .
  printf 'one\n' > mixed.txt; printf 'a\n' > staged.txt; printf 'gone\n' > deleted.txt; printf 'old name\n' > old.txt
  printf 'x\n' > ./-leading.txt
  git add -A && git commit -qm base
  printf 'one\nstaged line\n' > mixed.txt; git add mixed.txt
  printf 'one\nstaged line\nunstaged line\n' > mixed.txt
  printf 'a\nb\n' > staged.txt; git add staged.txt
  rm deleted.txt
  git mv old.txt new.txt
  printf 'changed\n' > ./-leading.txt
  printf 'fresh\n' > untracked.txt
  printf 'q\n' > 'quo"te'"'"'s.txt'; printf 'nl\n' > "$(printf 'new\nline.txt')"
  printf 'sp\n' > 'with  space.txt'; printf 'glob\n' > 'star*.txt'
}
CWD=$SB/work sx /bin/bash -c "R='$R'; $(declare -f make_repo); make_repo" || echo "fixture repository failed"

sx ruby -rjson -e 'File.write(ARGV[0], JSON.generate([
  { "message" => "refactor: rename old to new", "files" => ["new.txt"] },
  { "message" => "feat: odd names", "files" => ["-leading.txt", "quo\"te\x27s.txt", "new\nline.txt", "with  space.txt", "star*.txt"] },
  { "message" => "feat: rest", "files" => ["mixed.txt", "staged.txt", "deleted.txt", "untracked.txt"] }]))' "$SB/plan.json"

# index bytes, refs, staged diff, status, and every working file's bytes
snap() {
  CWD=$R sx /bin/bash -c '
    echo "index $(shasum -a 256 .git/index | cut -c1-64)"
    git for-each-ref --format="%(refname) %(objectname)"; echo "HEAD $(git rev-parse HEAD)"
    echo "staged-diff $(GIT_OPTIONAL_LOCKS=0 git diff --cached --binary | shasum -a 256 | cut -c1-64)"
    echo "status $(GIT_OPTIONAL_LOCKS=0 git status --porcelain=v1 -uall | tr "\n" "|")"
    find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
    echo "commits $(git rev-list --count HEAD)"'
}
hgit() { CWD=$R hb git "$@"; }
dry_run() { hgit commit -n </dev/null; }
identical() { snap > "$SB/$1.snap"; /usr/bin/diff "$SB/before.snap" "$SB/$1.snap" && echo identical; }
answer_no() { printf 'n\n' | hgit commit -w 2>&1 | tail -2 | sed 's/ *$//'; return "${PIPESTATUS[1]}"; }
answer_eof() { hgit commit -w </dev/null 2>&1 | tail -2 | sed 's/ *$//'; return "${PIPESTATUS[0]}"; }
planner_input() { cat "$SB/planner-argv.log"; sed -n '/^Changed files/,/^Unified diff/p' "$SB/planner-prompt.txt" | grep '^{'; }
incomplete_plan() {
  cp "$SB/plan.json" "$SB/plan.full"
  sx ruby -rjson -e 'p = JSON.parse(File.read(ARGV[0])); File.write(ARGV[0], JSON.generate(p.first(2)))' "$SB/plan.json"
  hgit commit -y </dev/null 2>&1 | grep -v -E '^(Analyzing|  \[|        - |$|These files|  ")'
  local code=${PIPESTATUS[0]}
  cp "$SB/plan.full" "$SB/plan.json"
  return "$code"
}

snap > "$SB/before.snap"
state "the fixture has a partial stage, a staged rename, an unstaged deletion, and untracked unusual names" "$(cat <<'EOF'
 M -leading.txt| D deleted.txt|MM mixed.txt|R  old.txt -> new.txt|M  staged.txt|?? "new\nline.txt"|?? "quo\"te's.txt"|?? star*.txt|?? untracked.txt|?? "with  space.txt"|
EOF
)" sed -n 's/^status //p' "$SB/before.snap"

check "dry run is planned from exact paths" "$(cat <<'EOF'
Analyzing 10 changed file(s) with claude (sonnet)...

  [1] refactor: rename old to new
        - "new.txt"  (renamed from "old.txt")
  [2] feat: odd names
        - "-leading.txt"
        - "quo\"te's.txt"
        - "new\nline.txt"
        - "with  space.txt"
        - "star*.txt"
  [3] feat: rest
        - "mixed.txt"  (staged+unstaged: whole file)
        - "staged.txt"
        - "deleted.txt"  (deleted)
        - "untracked.txt"

These files have staged and unstaged changes; a commit takes the whole working file:
  "mixed.txt"

(dry run — no commits made; index and working tree unchanged)
[exit 0]
EOF
)" dry_run

state "the dry run left index bytes, refs, staged diff, status, files, and history identical" "identical" identical after-dry

state "the planner got -p --model sonnet and every path as a JSON line" "$(cat <<'EOF'
-p --model sonnet
{"path":"-leading.txt","status":"M"}
{"path":"deleted.txt","status":"D"}
{"path":"mixed.txt","status":"M"}
{"path":"new\nline.txt","status":"A"}
{"path":"new.txt","status":"R","from":"old.txt"}
{"path":"quo\"te's.txt","status":"A"}
{"path":"staged.txt","status":"M"}
{"path":"star*.txt","status":"A"}
{"path":"untracked.txt","status":"A"}
{"path":"with  space.txt","status":"A"}
EOF
)" planner_input

check "declining the confirmation commits nothing" "$(cat <<'EOF'
Create 3 commit(s)? [y/N]
Cancelled; nothing was committed.
[exit 1]
EOF
)" answer_no

check "end of input at the confirmation commits nothing" "$(cat <<'EOF'
Create 3 commit(s)? [y/N]
Cancelled; nothing was committed.
[exit 1]
EOF
)" answer_eof

state "after the declined and EOF confirmations the repository is identical" "identical" identical after-cancel

check "an incomplete plan is refused before any mutation" "$(cat <<'EOF'
The planner returned an unusable plan; nothing was staged or committed:
  - paths not assigned: "deleted.txt", "mixed.txt", "staged.txt", "untracked.txt"
[exit 1]
EOF
)" incomplete_plan

state "the refused plan also left the repository identical" "identical" identical after-refused

# ---------------------------------------------------------------- (b) PR snapshots
sandbox pr
STATE="$SB/gh-state.json"; GHLOG="$SB/gh.log"; : > "$GHLOG"
sx ruby -e 'require ARGV[0]; FakeGh.install(ARGV[1], ARGV[2], ARGV[3])' "$REPO/test/support/fake_gh.rb" "$SB/fix" "$STATE" "$GHLOG"
A=$(printf 'a%.0s' {1..40}); B=$(printf 'b%.0s' {1..40})
# gh_state ONE_EXTRA_JSON TWO_HEAD [ACTIONS_JSON]
EMPTY='{}'
gh_state() {
  sx ruby -rjson -e '
    lint = [{ "__typename" => "CheckRun", "name" => "rspec", "status" => "COMPLETED", "conclusion" => "SUCCESS" },
            { "__typename" => "CheckRun", "name" => "lint", "status" => "COMPLETED", "conclusion" => "FAILURE", "detailsUrl" => "https://ci.example.test/lint" }]
    one = { "title" => "one", "state" => "OPEN", "head" => "a" * 40, "checks" => 250, "reviews" => 130 }.merge(JSON.parse(ARGV[1]))
    two = { "title" => "two", "state" => "OPEN", "head" => ARGV[2] * 40, "checks" => lint, "reviews" => 2 }
    File.write(ARGV[0], JSON.generate({ "repo" => "team/one", "prs" => { "team/one#42" => one, "team/two#42" => two }, "actions" => JSON.parse(ARGV[3]) }))' \
    "$STATE" "${1:-$EMPTY}" "${2:-b}" "${3:-$EMPTY}"
}
strip() { LANG=en_US.UTF-8 /usr/bin/sed -E $'s/\x1b\\[[0-9;]*m//g'; }
pr() { hb pr "$@" 2>&1 | strip; return "${PIPESTATUS[0]}"; }
first() { local out code; out=$(pr "$@"); code=$?; printf '%s\n' "$out" | head -1; return $code; }
listed() { pr update -u | grep -E "$1"; return "${PIPESTATUS[0]}"; }
rows() { q "select repo, number, substr(head_sha,1,7), checks_complete, reviews_complete, refresh_outcome, json_array_length(check_runs_json), json_array_length(review_nodes_json) from prs order by id; select pr_id, count(*) from check_runs group by pr_id order by pr_id"; }
observation() { q "select head_sha, fetched_at, check_runs_json, review_nodes_json from prs where repo='team/one'" | sha; }
stale_report() { pr green; pr status team/one#42; }
mutation_count() { mutations | /usr/bin/wc -l | /usr/bin/tr -d ' '; }
graphql_calls() { /usr/bin/grep -c '"api","graphql"' "$GHLOG"; }
mutations() { /usr/bin/grep -E '"pr","(merge|ready|comment)"' "$GHLOG" | /usr/bin/sed 's/,"--body-file","[^"]*"//'; }

gh_state
check "track by URL in team/one" $'Now tracking team/one#42: one\n[exit 0]' first track https://github.com/team/one/pull/42
check "track by owner/name#N in team/two (same number)" $'Now tracking team/two#42: two\n[exit 0]' first track team/two#42
check "a bare 42 that is already tracked resolves without a fetch" $'Already tracking team/one#42\n[exit 0]' pr track 42
check "a destructive bare 42 is ambiguous across the two repositories" \
  $'ERROR: Ambiguous PR #42 (team/one#42, team/two#42); use owner/name#42 or its URL\n[exit 1]' pr rm 42

check "a forced refresh lists both rows with their own checks" "$(cat <<'EOF'
1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 one
2. team/two#42 [o 　❌   1/  2]   2a/-cr branch-42 two
[exit 0]
EOF
)" listed "^[12]\. "

state "two distinct rows with qualified identity, head, completeness, and check ownership" "$(cat <<EOF
team/one|42|aaaaaaa|1|1|fresh|250|130
team/two|42|bbbbbbb|1|1|fresh|2|2
1|250
2|2
EOF
)" rows

gh_state '{"fail":{"checks":{"3":"exit"}}}'
check "a failed checks page makes the snapshot incomplete" "$(cat <<'EOF'
  incomplete team/one#42: checks: page 3 failed: gh exited 1: HTTP 502: Bad Gateway (https://api.github.com/graphql)
1. team/one#42 [o 　❓ 200/200] 130a/-cr branch-42 incomplete one
[exit 0]
EOF
)" listed '^  incomplete|^1\. '
check "an incomplete snapshot is never green" $'No PRs match.\n[exit 0]' pr green

gh_state
pr update -u >/dev/null
check "after a complete refresh team/one#42 is green" $'42\n[exit 0]' pr green -n
observation > "$SB/observed.before"
gh_state "{\"head_at\":{\"checks\":{\"2\":\"$B\"}}}"
check "a head change between pages fails the refresh and marks the row stale" "$(cat <<'EOF'
  refresh failed team/one#42: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)
1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 stale one
[exit 0]
EOF
)" listed '^  refresh failed|^1\. '
state "the earlier observation (head, fetched_at, checks, reviews) is kept byte-identical" "$(cat "$SB/observed.before")" \
  observation
check "a stale snapshot is not green and status reports it" "$(cat <<'EOF'
No PRs match.
team/one#42
one
open
250 success
snapshot stale: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)
https://github.com/team/one/pull/42
[exit 1]
EOF
)" stale_report

gh_state "{\"head\":\"$B\"}"
check "a consistent new revision refreshes fresh at the new head" $'1. team/one#42 [o 　✅ 250/250] 130a/-cr branch-42 one\n[exit 0]' \
  listed '^1\. '
state "team/one#42 now records head bbbbbbb, fresh; team/two#42 is unchanged" $'team/one|bbbbbbb|fresh|\nteam/two|bbbbbbb|fresh|' \
  q "select repo, substr(head_sha,1,7), refresh_outcome, refresh_error from prs order by id"

# ---------------------------------------------------------------- target-set actions
gh_state "{\"head\":\"$B\"}" b '{"team/two#42:merge":{"exit":1,"stderr":"Pull request team/two#42 is not mergeable: the base branch policy prohibits the merge"}}'
/bin/cat > "$SB/edit-strategy.sh" <<'SH'
/usr/bin/sed -i '' 's/^strategy:.*$/strategy: squash/' "$1"
SH
/bin/cat > "$SB/edit-fast.sh" <<'SH'
printf 'prs:\n- team/one#42\nstrategy: fast\n' > "$1"
SH
/bin/cat > "$SB/edit-nonsense.sh" <<'SH'
printf 'prs:\n- team/one#42\n- nonsense\n' > "$1"
SH
check "single merge of team/one#42 reaches gh once" $'fake gh: merge team/one#42\n✓ team/one#42 merge\n[exit 0]' pr merge team/one#42 --squash
check "single merge of team/two#42 reports the injected failure" "$(cat <<'EOF'
Pull request team/two#42 is not mergeable: the base branch policy prohibits the merge
fake gh: merge team/two#42
✗ team/two#42 merge: gh failed (exit 1)
[exit 1]
EOF
)" pr merge team/two#42 --squash
before_mutations=$(mutation_count)
check "conflicting strategies are refused before gh (single)" $'ERROR: merge: choose one of --merge, --squash, --rebase\n[exit 1]' pr merge team/one#42 --squash --rebase
ENVX+=(EDIT_SCRIPT="$SB/edit-fast.sh")
check "an invalid strategy is refused before gh (bulk)" $'Invalid selection: merge: strategy must be one of merge, squash, rebase or blank\n[exit 1]' pr mmerge
ENVX[${#ENVX[@]}-1]=EDIT_SCRIPT="$SB/edit-nonsense.sh"
check "an unknown target is refused before gh (bulk)" $'Invalid selection: Not a PR reference: nonsense\n[exit 1]' pr mmerge
check "an unknown target is refused before gh (single)" $'ERROR: Not a PR reference: nonsense\n[exit 1]' pr merge nonsense
state "no gh mutation happened during the four refusals" "$before_mutations" mutation_count
ENVX[${#ENVX[@]}-1]=EDIT_SCRIPT="$SB/edit-strategy.sh"
check "bulk mmerge over the edited target set reports each target and the total" "$(cat <<'EOF'
fake gh: merge team/one#42
✓ team/one#42 merge
Pull request team/two#42 is not mergeable: the base branch policy prohibits the merge
fake gh: merge team/two#42
✗ team/two#42 merge: gh failed (exit 1)
merge: 1 succeeded, 1 failed
[exit 1]
EOF
)" pr mmerge
state "gh received exactly the four squash merges, by URL, for the two qualified targets" "$(cat <<'EOF'
["pr","merge","https://github.com/team/one/pull/42","--squash"]
["pr","merge","https://github.com/team/two/pull/42","--squash"]
["pr","merge","https://github.com/team/one/pull/42","--squash"]
["pr","merge","https://github.com/team/two/pull/42","--squash"]
EOF
)" mutations
unset 'ENVX[${#ENVX[@]}-1]'

# ---------------------------------------------------------------- monitoring
sandbox monitor
STATE="$SB/gh-state.json"; GHLOG="$SB/gh.log"; : > "$GHLOG"
sx ruby -e 'require ARGV[0]; FakeGh.install(ARGV[1], ARGV[2], ARGV[3])' "$REPO/test/support/fake_gh.rb" "$SB/fix" "$STATE" "$GHLOG"
# st ONE_KIND ONE_HEAD TWO_KIND TWO_HEAD   KIND: pending | failing | passing
st() {
  sx ruby -rjson -e '
    node = { "pending" => { "__typename" => "CheckRun", "name" => "build", "status" => "IN_PROGRESS", "conclusion" => nil },
             "failing" => { "__typename" => "CheckRun", "name" => "lint", "status" => "COMPLETED", "conclusion" => "FAILURE" },
             "passing" => { "__typename" => "CheckRun", "name" => "lint", "status" => "COMPLETED", "conclusion" => "SUCCESS" } }
    pr = ->(t, kind, head) { { "title" => t, "state" => "OPEN", "head" => head * 40, "checks" => [node.fetch(kind)], "reviews" => 0 } }
    File.write(ARGV[0], JSON.generate({ "repo" => "team/one", "prs" => { "team/one#42" => pr.("one", ARGV[1], ARGV[2]), "team/two#42" => pr.("two", ARGV[3], ARGV[4]) } }))' \
    "$STATE" "$@"
}
mon() { hb pr-monitor --once 2>&1 | /usr/bin/sed 1d; return "${PIPESTATUS[0]}"; }
notes() { /usr/bin/grep -c '^terminal-notifier ' "$SB/tools.log" 2>/dev/null || echo 0; }
st pending a pending b
hb pr track team/one#42 >/dev/null 2>&1; hb pr track team/two#42 >/dev/null 2>&1
check "first cycle records baselines for both same-number PRs without notifying" "$(cat <<'EOF'
team/one#42 checks baseline pending at aaaaaaa: baseline
team/one#42 review baseline review_required at aaaaaaa: baseline
team/two#42 checks baseline pending at bbbbbbb: baseline
team/two#42 review baseline review_required at bbbbbbb: baseline
[exit 0]
EOF
)" mon
check "a repeated cycle (a new process) is silent" $'\n[exit 0]' mon
st failing a pending b
check "team/one#42 failing produces exactly one event; team/two#42 stays silent" $'team/one#42 checks pending → failing at aaaaaaa: notified\n[exit 0]' mon
check "a restart after the event is silent" $'\n[exit 0]' mon
st failing a failing b
check "the same transition in team/two#42 is its own event" $'team/two#42 checks pending → failing at bbbbbbb: notified\n[exit 0]' mon
st pending c failing b
check "a new head in team/one#42 is a new event" $'team/one#42 checks failing → pending at ccccccc: notified\n[exit 0]' mon
check "and repeating it is silent" $'\n[exit 0]' mon
state "three notifications in total, one per transition" "3" notes
state "one checkpoint per PR and channel, qualified by repository (review compares state only, so its head stays at the baseline)" "$(cat <<'EOF'
team/one|42|checks|ccccccc|pending
team/one|42|review|aaaaaaa|review_required
team/two|42|checks|bbbbbbb|failing
team/two|42|review|bbbbbbb|review_required
EOF
)" q "select repo, number, channel, substr(head_sha,1,7), state from pr_monitor_checkpoints order by repo, channel"
state "monitoring never asked gh to mutate anything" "" mutations

incomplete "live GitHub mutation (merge, ready, comment) against a real repository" \
  "adapter-limited proof: every gh call went to test/support/fake_gh.rb; no live GitHub account, network, or mutation was used, by design"
