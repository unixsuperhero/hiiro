# 1. The procedure itself: the sandbox environment every scenario uses.
source "$(dirname "$0")/lib.sh"
sandbox

check "only fixtures, the pinned ruby, and the checkout resolve on the sandbox PATH" "$(cat <<EOF
ruby -> \$SB/rubybin/ruby
h -> $REPO/bin/h
t -> $REPO/bin/t
tt -> $REPO/bin/tt
gh -> none
claude -> none
omp -> none
codex -> none
herdr -> none
tuios -> none
tmux -> none
pbcopy -> \$SB/fix/pbcopy
pbpaste -> \$SB/fix/pbpaste
open -> \$SB/fix/open
osascript -> \$SB/fix/osascript
launchctl -> \$SB/fix/launchctl
terminal-notifier -> \$SB/fix/terminal-notifier
[exit 0]
EOF
)" sx /bin/bash -c 'for n in ruby h t tt gh claude omp codex herdr tuios tmux pbcopy pbpaste open osascript launchctl terminal-notifier; do printf "%s -> %s\n" "$n" "$(command -v $n || echo none)"; done'

check "the environment holds only sandbox values and no terminal or multiplexer identity" "$(cat <<EOF
HOME=\$SB/home
USER=accept
LOGNAME=accept
LANG=en_US.UTF-8
TERM=dumb
SB=\$SB
PATH=\$SB/fix:\$SB/rubybin:$REPO/bin:/usr/bin:/bin
RUBYLIB=$REPO/lib
GEM_HOME=\$SB/gem-home
GEM_PATH=$GEMS
TMPDIR=\$SB/tmp
EDITOR=\$SB/fix/editor
VISUAL=\$SB/fix/editor
[exit 0]
EOF
)" sx /usr/bin/env

check "hiiro loads from the checkout; no installed hiiro gem is visible" "$(cat <<EOF
$REPO/lib/hiiro.rb
[]
[exit 0]
EOF
)" sx ruby -e 'require "hiiro"; puts $LOADED_FEATURES.grep(%r{/hiiro\.rb\z}); p Gem::Specification.find_all_by_name("hiiro").map(&:full_name)'

check "the database is the default file under the sandbox HOME and starts absent" "$(cat <<'EOF'
$SB/home/.config/hiiro/hiiro.db
false
[exit 0]
EOF
)" sx ruby -e 'require "hiiro"; puts Hiiro::Config.path("hiiro.db"); p File.exist?(Hiiro::Config.path("hiiro.db"))'

# Metadata of the caller's real home that no scenario may change; 99 compares.
# Read only: names, sizes, and modification times, never contents.
LIVE=${HIIRO_ACCEPTANCE_LIVE_HOME:-$HOME}
live_snapshot() {
  local dir
  for dir in "$LIVE/bin" "$LIVE/.config/hiiro" "$LIVE/.local/share/hiiro" "$LIVE/Library/LaunchAgents" "$("$RUBY" -e 'print Gem.dir')/specifications"; do
    echo "## $dir"
    [ -d "$dir" ] && /usr/bin/find "$dir" -maxdepth 1 ! -name hiiro.db ! -name 'hiiro.db-*' -exec /usr/bin/stat -f '%N %z %m' {} + | LC_ALL=C /usr/bin/sort
  done
}
live_snapshot > "$OUT/live-before.txt"
/usr/bin/stat -f '%N %z %m' "$LIVE/.config/hiiro/hiiro.db" > "$OUT/live-db-before.txt" 2>&1
