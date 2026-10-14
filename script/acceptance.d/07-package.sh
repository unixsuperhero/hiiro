# 7. The package: build the gem from a copy of the checkout, install it with
# its dependencies from local .gem files into a disposable GEM_HOME, and run
# the installed entrypoints with no checkout load path or live install.
source "$(dirname "$0")/lib.sh"
sandbox
GH="$SB/gem-home"
SRC="$SB/src"
VERSION=$(/usr/bin/sed -n 's/^ *VERSION = "\(.*\)"$/\1/p' "$REPO/lib/hiiro/version.rb")
GEM_FILE="$SRC/hiiro-$VERSION.gem"
PKG="$GH/gems/hiiro-$VERSION"
NORM=("s/$VERSION/VERSION/g")
/bin/mkdir -p "$SRC" "$SB/deps" "$SB/buildhome" "$H/bin" "$SB/proj/work" "$SB/media"

# The gemspec lists `git ls-files`, so the copy is its own repository holding
# the checkout's tracked and untracked-not-ignored files.
(cd "$REPO" && /usr/bin/git ls-files -co --exclude-standard -z) | (cd "$REPO" && /usr/bin/rsync -a --from0 --files-from=- ./ "$SRC/")
(cd "$SRC" && /usr/bin/git init -q && /usr/bin/git add -A)
# What the gemspec keeps: everything but tests, specs, git metadata, and Gemfile*.
# (Its own-file exclusion compares against a relative __FILE__ under `gem
# build`, so hiiro.gemspec ships too.)
PKG_FILES=$(cd "$SRC" && /usr/bin/git ls-files | /usr/bin/grep -Ev '^(test/|spec/|features/|\.git|\.github|\.circleci|appveyor|Gemfile)' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
echo "package source: $(cd "$SRC" && /usr/bin/git ls-files | /usr/bin/wc -l | /usr/bin/tr -d ' ') files copied from $REPO, $PKG_FILES packaged"

# Build/install environment: nothing from the checkout, the rbenv gem dir, or HOME.
bx() {
  (cd "${BX_CWD:-$SB/work}" && /usr/bin/env -i HOME="$SB/buildhome" LANG=en_US.UTF-8 PATH="$SB/rubybin:/usr/bin:/bin" \
    GEM_HOME="$GH" GEM_PATH="$GH" "$SB/limit" "${LIMIT:-300}" ruby "$@")
}
# Installed environment: PATH = sandbox ~/bin + gem bin + fixtures + ruby link +
# system; no RUBYLIB; RUBYOPT loads a recorder of every loaded feature.
/bin/cat > "$SB/features.rb" <<'RB'
at_exit do
  File.open(ENV.fetch('FEATURES_OUT'), 'a') { |f| f.puts "## #{$0}"; $LOADED_FEATURES.each { |path| f.puts path } }
end
RB
IXE=()
ix() {
  (cd "${IX_CWD:-$SB/proj}" && /usr/bin/env -i HOME="$H" USER=accept LANG=en_US.UTF-8 TERM=dumb SB="$SB" \
    PATH="$H/bin:$GH/bin:$SB/fix:$SB/rubybin:/usr/bin:/bin" GEM_HOME="$GH" GEM_PATH="$GH" TMPDIR="$SB/tmp" \
    EDITOR="$SB/fix/editor" VISUAL="$SB/fix/editor" RUBYOPT="-r$SB/features.rb" FEATURES_OUT="$SB/features.txt" \
    ${IXE[@]+"${IXE[@]}"} "$SB/limit" "${LIMIT:-120}" "$@")
}
# Read-write sqlite3 on the sandbox database (read-only mode cannot open its WAL).
dbq() { /usr/bin/sqlite3 -separator '|' "$DB" "$@"; }

# --- build and install --------------------------------------------------------

build() { BX_CWD="$SRC" bx -S gem build hiiro.gemspec 2>&1 | /usr/bin/grep -E '^  (Successfully|Name|Version|File)'; }
check "gem build makes hiiro-VERSION.gem from the copy" "$(cat <<'EOF'
  Successfully built RubyGem
  Name: hiiro
  Version: VERSION
  File: hiiro-VERSION.gem
[exit 0]
EOF
)" build
echo "package identity: hiiro $VERSION, $(/usr/bin/stat -f %z "$GEM_FILE") bytes, sha256 $(sha "$GEM_FILE")"

contents() {
  local list
  list=$(cd "$SB/tmp" && /usr/bin/tar -xOf "$GEM_FILE" data.tar.gz | /usr/bin/tar -tzf - | LC_ALL=C /usr/bin/sort)
  echo "data entries: $(printf '%s\n' "$list" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  echo "bin/h-*: $(printf '%s\n' "$list" | /usr/bin/grep -c '^bin/h-')"
  echo "exe: $(printf '%s\n' "$list" | /usr/bin/grep '^exe/' | /usr/bin/paste -sd ' ' -)"
  echo "lib/hiiro/mcp: $(printf '%s\n' "$list" | /usr/bin/grep '^lib/hiiro/mcp' | /usr/bin/paste -sd ' ' -)"
  echo "docs/h-mcp.md: $(printf '%s\n' "$list" | /usr/bin/grep -c '^docs/h-mcp.md$')"
  echo "test/: $(printf '%s\n' "$list" | /usr/bin/grep -c '^test/')"
  echo "bin/lib/: $(printf '%s\n' "$list" | /usr/bin/grep -c '^bin/lib/')"
}
state "the package ships every bin/h-* command, exe/{h,hiiro,t,tt}, the MCP library and doc, and no tests or bin/lib" "$(cat <<EOF
data entries: $PKG_FILES
bin/h-*: 77
exe: exe/h exe/hiiro exe/t exe/tt
lib/hiiro/mcp: lib/hiiro/mcp.rb lib/hiiro/mcp/catalog.rb lib/hiiro/mcp/registry.rb lib/hiiro/mcp/sync.rb
docs/h-mcp.md: 1
test/: 0
bin/lib/: 0
EOF
)" contents

# Dependencies come only from the isolated set's .gem cache; each file is
# installed without resolution, and activation below proves the set complete.
/bin/cp "$GEMS"/cache/*.gem "$GEM_FILE" "$SB/deps/"
install_gems() { bx -S gem install --local --no-document --ignore-dependencies --install-dir "$GH" --bindir "$GH/bin" "$SB"/deps/*.gem 2>&1 | /usr/bin/tail -1; }
check "gem install --local puts hiiro and the 21 dependency .gem files in the disposable GEM_HOME" "$(cat <<'EOF'
22 gems installed
[exit 0]
EOF
)" install_gems

check "activating hiiro resolves every runtime dependency from GEM_HOME only" "$(cat <<'EOF'
hiiro-VERSION from $SB/gem-home/gems/hiiro-VERSION
Gem.path: $SB/gem-home
runtime deps: awesome_print event_stream_parser faraday front_matter_parser mcp pry sequel sqlite3
[exit 0]
EOF
)" bx -e 'gem "hiiro"; s = Gem.loaded_specs["hiiro"]; puts "#{s.full_name} from #{s.full_gem_path}"; puts "Gem.path: #{Gem.path.join(":")}"; s.runtime_dependencies.each { |d| gem d.name }; puts "runtime deps: #{s.runtime_dependencies.map(&:name).sort.join(" ")}"'

binstubs() { local b; for b in h hiiro t tt; do [ -x "$GH/bin/$b" ] && /usr/bin/grep -q "load Gem.activate_bin_path('hiiro', '$b'" "$GH/bin/$b" && echo "$b -> hiiro"; done; }
check "the gem installs binstubs h, hiiro, t, tt that activate the hiiro gem" "$(cat <<'EOF'
h -> hiiro
hiiro -> hiiro
t -> hiiro
tt -> hiiro
[exit 0]
EOF
)" binstubs

# --- installed entrypoints ----------------------------------------------------

check "installed h resolves from GEM_HOME and answers ping and version" "$(cat <<'EOF'
$SB/gem-home/bin/h
pong
VERSION
[exit 0]
EOF
)" ix /bin/sh -c 'command -v h && h ping && h version'

: > "$SB/features.txt"
ix h ping > /dev/null 2>&1
ix t --help > /dev/null 2>&1
ix hiiro version > /dev/null 2>&1
ix tt --help > /dev/null 2>&1
origins() {
  local f="$SB/features.txt"
  echo "processes recorded: $(/usr/bin/grep -c '^## ' "$f")"
  echo "loaded $PKG/lib/hiiro.rb: $(/usr/bin/grep -c "^$PKG/lib/hiiro.rb\$" "$f")"
  echo "hiiro features outside GEM_HOME: $(/usr/bin/grep -v '^## ' "$f" | /usr/bin/grep '/hiiro' | /usr/bin/grep -vc "^$GH/")"
  echo "features from the checkout: $(/usr/bin/grep -c "^$REPO/" "$f")"
  echo "features from any rbenv gem dir: $(/usr/bin/grep -c '/lib/ruby/gems/' "$f")"
}
state "installed h, t, tt, and hiiro load hiiro only from GEM_HOME, nothing from the checkout or the rbenv gem dir" "$(cat <<'EOF'
processes recorded: 4
loaded $SB/gem-home/gems/hiiro-VERSION/lib/hiiro.rb: 4
hiiro features outside GEM_HOME: 0
features from the checkout: 0
features from any rbenv gem dir: 0
EOF
)" origins

check "t and tt answer help from the gem without creating a database" "$(cat <<'EOF'
t help lines > 5: yes
tt help lines > 5: yes
database: absent
[exit 0]
EOF
)" ix /bin/sh -c 'for b in t tt; do n=$($b --help 2>&1 | wc -l); [ "$n" -gt 5 ] && echo "$b help lines > 5: yes"; done; [ -e "$HOME/.config/hiiro/hiiro.db" ] && echo "database: present" || echo "database: absent"'

# --- setup into the sandbox ~/bin ---------------------------------------------

# A user's own ~/bin/h-notify exists before setup and must be kept.
printf '#!/bin/sh\necho user notify\n' > "$H/bin/h-notify"; /bin/chmod 755 "$H/bin/h-notify"
NOTIFY_SHA=$(sha "$H/bin/h-notify")

plan_summary() { ix h setup | /usr/bin/grep -Ev '^  (missing|unchanged) '; }
check "h setup plans 79 missing assets, keeps the user's h-notify as a collision, and writes nothing" "$(cat <<'EOF'
Source: hiiro VERSION (gem $SB/gem-home/gems/hiiro-VERSION)
Commands: ~/bin  Plugins: ~/.config/hiiro/plugins  Manifest: ~/.config/hiiro/install-manifest.json

  collision      ~/bin/h-notify                      bin/h-notify        kept (not written by hiiro; --adopt NAME to manage it)

79 missing, 1 collision
Run `h setup --apply` to write 79 assets.
[exit 0]
EOF
)" plan_summary
state "the plan wrote nothing: ~/bin holds only the user's file and no manifest exists" "$(cat <<'EOF'
h-notify
manifest: absent
EOF
)" /bin/sh -c "ls '$H/bin'; [ -e '$H/.config/hiiro/install-manifest.json' ] && echo 'manifest: present' || echo 'manifest: absent'"

apply() { ix h setup --apply | /usr/bin/tail -1; }
check "h setup --apply installs the 79 assets" "$(cat <<'EOF'
Applied: 79 installed
[exit 0]
EOF
)" apply

installed() {
  local bad=0 f name
  for f in "$PKG"/bin/h-*; do
    name=$(basename "$f")
    [ "$name" = h-notify ] && continue
    [ "$(sha "$f")" = "$(sha "$H/bin/$name")" ] && [ "$(/usr/bin/stat -f %Lp "$H/bin/$name")" = 755 ] || { bad=$((bad + 1)); echo "differs: $name"; }
  done
  echo "~/bin h-* byte- and mode-identical to the package: $(($(ls "$PKG"/bin/h-* | wc -l) - 1 - bad))"
  for f in "$PKG"/plugins/*.rb; do
    name=$(basename "$f")
    [ "$(sha "$f")" = "$(sha "$H/.config/hiiro/plugins/$name")" ] && echo "plugin $name identical, mode $(/usr/bin/stat -f %Lp "$H/.config/hiiro/plugins/$name")"
  done
  echo "user h-notify unchanged: $([ "$(sha "$H/bin/h-notify")" = "$NOTIFY_SHA" ] && echo yes || echo no)"
}
state "installed files are the package's bytes; the user's h-notify is untouched" "$(cat <<'EOF'
~/bin h-* byte- and mode-identical to the package: 76
plugin notify.rb identical, mode 644
plugin pins.rb identical, mode 644
plugin project.rb identical, mode 644
user h-notify unchanged: yes
EOF
)" installed

manifest() {
  ix ruby -rjson -e '
    assets = JSON.parse(File.read(ARGV[0]))["assets"]
    puts "records: #{assets.size}"
    puts "owners: #{assets.values.map { |r| r["owner"] }.tally}"
    puts "packages: #{assets.values.map { |r| "#{r["package"]} #{r["version"]}" }.uniq}"
    puts "roots: #{assets.values.map { |r| r["root"] }.uniq}"
    r = assets[File.join(ENV["HOME"], "bin/h-sha")]
    puts "h-sha: #{r.slice("asset", "source", "mode", "owner")} sha matches file: #{r["sha256"] == Digest::SHA256.file(File.join(ENV["HOME"], "bin/h-sha")).hexdigest}"
    puts "h-notify recorded: #{assets.key?(File.join(ENV["HOME"], "bin/h-notify"))}"' -rdigest "$H/.config/hiiro/install-manifest.json"
}
check "the manifest records each written asset with package identity, root, digest, and owner" "$(cat <<'EOF'
records: 79
owners: {"installed"=>79}
packages: ["hiiro VERSION"]
roots: ["$SB/gem-home/gems/hiiro-VERSION"]
h-sha: {"asset"=>"command", "source"=>"bin/h-sha", "mode"=>"0755", "owner"=>"installed"} sha matches file: true
h-notify recorded: false
[exit 0]
EOF
)" manifest

# Safe repeat installation.
check "a second plan is all unchanged apart from the user's collision" "$(cat <<'EOF'
1 collision, 79 unchanged
[exit 0]
EOF
)" /bin/sh -c "$(declare -f ix); IXE=(); GH='$GH' SB='$SB' H='$H'; ix h setup | tail -1"
SNAP1=$(cd "$H" && /usr/bin/find bin .config/hiiro -type f -exec /usr/bin/shasum -a 256 {} + | LC_ALL=C /usr/bin/sort)
check "a second --apply selects nothing" "$(cat <<'EOF'
Applied: nothing selected
[exit 0]
EOF
)" apply
state "every installed file and the manifest are byte-identical after the repeat" "identical" \
  /bin/sh -c "[ \"\$(cd '$H' && /usr/bin/find bin .config/hiiro -type f -exec /usr/bin/shasum -a 256 {} + | LC_ALL=C /usr/bin/sort)\" = '$SNAP1' ] && echo identical || echo changed"

# A user edit to an owned command is protected.
printf '\n# my local tweak\n' >> "$H/bin/h-pr"
PR_SHA=$(sha "$H/bin/h-pr")
check "after a user edit, the plan reports h-pr user-modified and --apply keeps it" "$(cat <<'EOF'
  user-modified  ~/bin/h-pr      bin/h-pr      kept (changed since hiiro wrote it)
  collision      ~/bin/h-notify  bin/h-notify  kept (not written by hiiro; --adopt NAME to manage it)
1 user-modified, 1 collision, 78 unchanged
Applied: nothing selected
[exit 0]
EOF
)" /bin/sh -c "$(declare -f ix); IXE=(); GH='$GH' SB='$SB' H='$H'; ix h setup | grep -E '^  (user-modified|collision)|unchanged\$'; ix h setup --apply | tail -1"
state "the edited h-pr and the user's h-notify are byte-identical afterwards" "$(cat <<'EOF'
h-pr: kept
h-notify: kept
EOF
)" /bin/sh -c "[ \"\$(/usr/bin/shasum -a 256 '$H/bin/h-pr' | cut -d' ' -f1)\" = '$PR_SHA' ] && echo 'h-pr: kept'; [ \"\$(/usr/bin/shasum -a 256 '$H/bin/h-notify' | cut -d' ' -f1)\" = '$NOTIFY_SHA' ] && echo 'h-notify: kept'"

provenance() {
  ix h bin docs --json | ix ruby -rjson -e '
    JSON.parse($stdin.read).select { |e| %w[notify pr sha ping].include?(e["name"]) }.sort_by { |e| e["name"] }
      .each { |e| puts [e["name"], e["kind"], e["origin"], e["source"]].join(" | ") }'
}
check "h bin docs --json labels user, modified, managed, and package origins with their sources" "$(cat <<'EOF'
notify | external | user | $SB/home/bin/h-notify
ping | inline | package hiiro VERSION | $SB/gem-home/gems/hiiro-VERSION/lib/hiiro/root_commands.rb:24
pr | external | modified (managed hiiro VERSION) | $SB/home/bin/h-pr
sha | external | managed hiiro VERSION | $SB/home/bin/h-sha
[exit 0]
EOF
)" provenance

check "h dispatches to the installed ~/bin copy and the user's h-notify runs as written" "$(cat <<'EOF'
user notify
[exit 0]
EOF
)" ix h notify

# --- bundled MCP over a local stdio transport ---------------------------------

/bin/cat > "$SB/stdio_server.rb" <<'RB'
# Harmless stdio MCP fixture: one read-only tool reporting its directory and an env value.
require 'json'
$stdout.sync = true
$stdin.each_line do |line|
  request = JSON.parse(line)
  next unless request.key?('id')
  response = { 'jsonrpc' => '2.0', 'id' => request['id'] }
  case request['method']
  when 'initialize'
    response['result'] = { 'protocolVersion' => request.dig('params', 'protocolVersion'), 'capabilities' => { 'tools' => {} },
                           'serverInfo' => { 'name' => 'stdio-fixture', 'version' => '1' } }
  when 'tools/list'
    response['result'] = { 'tools' => [{ 'name' => 'where', 'description' => 'Report the working directory and greeting.',
                                         'inputSchema' => { 'type' => 'object', 'properties' => { 'text' => { 'type' => 'string' } }, 'required' => ['text'] },
                                         'annotations' => { 'readOnlyHint' => true } }] }
  when 'tools/call'
    response['result'] = { 'isError' => false, 'content' => [{ 'type' => 'text', 'text' => 'ok' }],
                           'structuredContent' => { 'cwd' => Dir.pwd, 'greeting' => ENV['FIXTURE_GREETING'], 'echo' => request.dig('params', 'arguments', 'text') } }
  else
    response['error'] = { 'code' => -32601, 'message' => 'method not found' }
  end
  puts JSON.generate(response)
end
RB
printf '{"mcpServers":{"local":{"command":"ruby","args":["%s"],"cwd":"work","env":{"FIXTURE_GREETING":"${env:MCP_TEST_GREETING}"}}}}\n' "$SB/stdio_server.rb" > "$SB/proj/mcp.json"
IXE=(MCP_TEST_GREETING=hello)
: > "$SB/features.txt"

check "h mcp add registers the stdio server from the config without connecting" "$(cat <<'EOF'
registered local
[exit 0]
EOF
)" ix h mcp add local --config "$SB/proj/mcp.json"
check "h mcp discover saves the server's tool list" "$(cat <<'EOF'
saved local: 1 tools
[exit 0]
EOF
)" ix h mcp discover local
tools_local() { ix h mcp tools local | /usr/bin/sed 's/ *$//'; }
check "h mcp tools reads the saved catalog offline (trailing padding trimmed)" "$(cat <<'EOF'
name   description
-------------------------------------------------
where  Report the working directory and greeting.
(1 rows)
[exit 0]
EOF
)" tools_local
call() { printf '{"text":"hi"}' | ix h mcp call local where --args-file - --data; }
check "h mcp call runs the tool in the configured cwd with the expanded env and stdin arguments" "$(cat <<'EOF'
{
  "cwd": "$SB/proj/work",
  "greeting": "hello",
  "echo": "hi"
}
[exit 0]
EOF
)" call
state "the registration and catalog are rows in the sandbox database; MCP code loaded only from GEM_HOME" "$(cat <<'EOF'
mcps: local|stdio
tool names: ["where"]
mcp library files from GEM_HOME: 4
mcp features outside GEM_HOME: 0
EOF
)" /bin/sh -c "echo \"mcps: \$(/usr/bin/sqlite3 '$DB' \"select name, json_extract(record_json, '\$.transport') from mcps\" | tr '\n' ' ' | sed 's/ \$//')\"
  echo \"tool names: \$(/usr/bin/sqlite3 '$DB' \"select json_extract(record_json, '\$.tools[0].name') from mcps\" | sed 's/.*/[\"&\"]/')\"
  echo \"mcp library files from GEM_HOME: \$(grep -E '^$PKG/lib/hiiro/mcp(\\.rb|/[a-z]+\\.rb)\$' '$SB/features.txt' | sort -u | wc -l | tr -d ' ')\"
  echo \"mcp features outside GEM_HOME: \$(grep -v '^## ' '$SB/features.txt' | grep -E '/mcp[-/.]' | grep -vc '^$GH/')\""
IXE=()

# --- utilities, profiles, and retained native wrappers -------------------------

printf 'a\0b\377' > "$SB/bytes.bin"
codec() {
  ix h encode b64 < "$SB/bytes.bin" > "$SB/bytes.b64"
  printf 'encoded: %s\n' "$(/usr/bin/od -An -c "$SB/bytes.b64" | /usr/bin/tr -s ' ' | /usr/bin/sed 's/ $//')"
  ix h decode b64 < "$SB/bytes.b64" > "$SB/bytes.out"
  echo "round trip identical: $([ "$(sha "$SB/bytes.bin")" = "$(sha "$SB/bytes.out")" ] && echo yes || echo no) ($(/usr/bin/stat -f %z "$SB/bytes.out") bytes)"
  printf 'form: %s\n' "$(printf 'a+b' | ix h decode form)"
  printf 'uri: %s\n' "$(printf 'a+b' | ix h decode uri)"
}
check "codecs round-trip NUL/0xFF bytes and keep percent versus form decoding" "$(cat <<'EOF'
encoded:  Y Q B i / w = =
round trip identical: yes (4 bytes)
form: a b
uri: a+b
[exit 0]
EOF
)" codec

check "time outputs: date and time from_unix and a signed diff" "$(cat <<'EOF'
1970-01-01T00:00:00.000Z
00:00:00.000
-2m
[exit 0]
EOF
)" ix /bin/sh -c 'h date from_unix 0 --utc; h time from_unix 0 --utc; h time diff 120 0'

if [ -x /opt/homebrew/bin/ffmpeg ] && [ -x /opt/homebrew/bin/ffprobe ]; then
  /bin/ln -s /opt/homebrew/bin/ffmpeg /opt/homebrew/bin/ffprobe "$SB/fix/"
  (cd "$SB/media" && "$SB/limit" 120 /opt/homebrew/bin/ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=25 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 -t 2 -c:v libx264 -g 25 -pix_fmt yuv420p -c:a aac -shortest in.mp4)
  media() {
    IX_CWD="$SB/media" ix h video resize in.mp4 180 > "$SB/media/resize.log" 2>&1
    echo "h video exit: $?"
    /opt/homebrew/bin/ffprobe -v error -show_entries stream=codec_type,codec_name,width,height -of csv=p=0 "$SB/media/in.180p.mp4"
  }
  check "h video resize writes a 240x180 h264 file (inspected with ffprobe)" "$(cat <<'EOF'
h video exit: 0
h264,video,240,180
aac,audio
[exit 0]
EOF
)" media
else
  incomplete "h video resize output" "no ffmpeg/ffprobe at /opt/homebrew/bin"
fi

/bin/mkdir -p "$H/.config/hiiro"
printf 'casts:\n  dir: %s\n' "$SB/casts" > "$H/.config/hiiro/profile.yml"
TODAY=$(/bin/date +%Y%m%d)
NORM+=("s/$TODAY/TODAY/g")
check "root profiles: directory profiles print their roots and profile.yml directs the cast names" "$(cat <<'EOF'
home: $SB/home
vim: $SB/home/.config/nvim
dotfiles: $SB/home/proj/home
cast: $SB/casts/TODAY000.cast
[exit 0]
EOF
)" ix /bin/sh -c 'echo "home: $(h home path)"; echo "vim: $(h vim path)"; echo "dotfiles: $(h dotfiles path)"; echo "cast: $(h asciinema nname)"'

check "retained native wrappers report a missing app bundle and a missing tmux client, exit 1, and write nothing" "$(cat <<'EOF'
h-sign: app bundle not found: /nonexistent.app
[exit 1]
ERROR: h jumplist needs a running tmux client; none was found
[exit 1]
jumplist dir: absent
[exit 0]
EOF
)" ix /bin/sh -c 'h sign verify /nonexistent.app; echo "[exit $?]"; h jumplist path; echo "[exit $?]"; [ -e "$HOME/.config/hiiro/jumplist" ] && echo "jumplist dir: present" || echo "jumplist dir: absent"'

# Any process whose command line names this sandbox (ps output is filtered in
# this shell; the check's own normalizing sed is skipped).
leftovers() {
  local listing; listing=$(/bin/ps -A -o pid=,command=)
  local line n=0
  while IFS= read -r line; do case $line in *"sed -E -e s#"*) ;; *"$SB"*) n=$((n + 1)); echo "$line" ;; esac; done <<< "$listing"
  [ "$n" -eq 0 ] && echo none
}
state "no process this scenario started is still running" "none" leftovers
