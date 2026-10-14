# The caller's real home is unchanged by the whole run (compared with the
# snapshot 00 took). The live database is reported, not judged: the person
# may use their own installed h while the procedure runs.
source "$(dirname "$0")/lib.sh"
SB=$OUT
if [ ! -f "$OUT/live-before.txt" ]; then
  incomplete "live home unchanged" "run scenario 00 in the same invocation first"
  exit 0
fi
LIVE=${HIIRO_ACCEPTANCE_LIVE_HOME:-$HOME}
live_snapshot() {
  local dir
  for dir in "$LIVE/bin" "$LIVE/.config/hiiro" "$LIVE/.local/share/hiiro" "$LIVE/Library/LaunchAgents" "$("$RUBY" -e 'print Gem.dir')/specifications"; do
    echo "## $dir"
    [ -d "$dir" ] && /usr/bin/find "$dir" -maxdepth 1 ! -name hiiro.db ! -name 'hiiro.db-*' -exec /usr/bin/stat -f '%N %z %m' {} + | LC_ALL=C /usr/bin/sort
  done
}
state "~/bin, ~/.config/hiiro (but the database), ~/.local/share/hiiro, LaunchAgents, and installed gem specs unchanged" \
  "$(/bin/cat "$OUT/live-before.txt")" live_snapshot
echo "live database before: $(/bin/cat "$OUT/live-db-before.txt")"
echo "live database after:  $(/usr/bin/stat -f '%N %z %m' "$LIVE/.config/hiiro/hiiro.db" 2>&1)"
state "no launchd job with the hiiro schedule prefix is registered" "" /bin/sh -c "/bin/launchctl list | /usr/bin/grep -F com.hiiro"
state "no sandbox process outlived the run" "" /bin/sh -c "/bin/ps -A -o command= | /usr/bin/grep -F '$OUT/sb/' | /usr/bin/grep -v grep"
