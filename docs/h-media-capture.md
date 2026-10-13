# Screen capture, amber-border crop, and terminal casts

Three separate recipes: `h screencap` records app windows from the screen, `h crop` crops a recording to the inside of an amber border, and `h asciinema` records terminal casts. They share nothing but `ffmpeg` / `ffprobe` (screencap, crop). Personal output directories and editor recipes come from `~/.config/hiiro/profile.yml`.

## h screencap

```text
h screencap app APP_NAME
h screencap start APP_NAME... [--screen=1] [--audio=0] [--audio-mode=separate] [--audio-bitrate=320k]
                              [--video-format=mov] [--scale=1] [--framerate=30] [--startup-wait=3]
                              [--out-dir=DIR] [--name=yt]
h screencap stop
h screencap status
```

- `app` prints `{:x=>..., :y=>..., :w=>..., :h=>...}` for the app's front window (AppleScript through System Events; the terminal needs Accessibility access). When the profile has a recipe for that name under `screencap.apps`, `app` first runs `open` with the recipe's `open` value, waits `wait` seconds (default 1), and reads the bounds of `process`.
- `start` reads each app's window bounds, scales them by `--scale`, makes width and height even (`yuv420p`), and starts one detached `ffmpeg` (`avfoundation`, own process group, stdin from a FIFO) that writes one H.264 file per window. Audio modes: `separate` (default; an extra `-audio.wav`, `pcm_s16le`), `first` (AAC in the first window's file), `all` (AAC in every file), `none` (also `--audio=none`). Formats: `mov` (default), `mp4` (both `+faststart`), `mkv`. Files are `OUT_DIR/NAME.YYYYMMDD-HHMMSS-APP_SLUG.FORMAT`; the ffmpeg log is `OUT_DIR/NAME.YYYYMMDD-HHMMSS.ffmpeg.log`.
- `stop` writes `q` to the FIFO and waits up to 30s for ffmpeg to finalize; if it does not, it sends SIGINT to the process group, then TERM after 30s, then KILL after 2s. It prints each output with its size.
- State lives in `~/.local/state/h-screencap/recording.json` (pid, command, outputs, log, rects, audio mode, FIFO). `start` refuses while a recorded pid is alive.

```js
// Hiiro::ScreenCapture::Plan (lib/hiiro/screen_capture.rb) is the command as a value
plan = { apps: ["Ghostty"], rects: [[0, 25, 1200, 800]], out_dir: "/m", session_name: "yt.20261013-120000",
         screen: "1", audio: "0", audio_mode: "separate", audio_bitrate: "320k", video_format: "mov", framerate: "30" }
plan.filter_graph // "[0:v]crop=1200:800:0:25,setpts=PTS-STARTPTS,fps=30,setsar=1[v0]"
plan.outputs      // ["/m/yt.20261013-120000-ghostty.mov", "/m/yt.20261013-120000-audio.wav"]
```

Profile section (defaults shown):

```yaml
screencap:
  out_dir: ~/Movies/h-screencap
  apps:                       # none by default
    codehiiro:                # the installed `h screencap codehiiro` / `ch` shortcut, as a recipe
      open: release/CodeHiiro.app
      process: CodeHiiro
      wait: 1
```

The installed `codehiiro` / `ch` subcommands are not hard-coded any more: `h screencap app codehiiro` runs that recipe (add a second key, e.g. `ch`, for the short name).

## h crop

`h crop INPUT OUTPUT [--frame=1] [--tolerance=60] [--inset=3]` is the Python adapter (`bin/h-crop`, needs `python3`, `ffmpeg`, `ffprobe`). It samples one frame, finds the amber (RGB 245,158,11) rectangle border within the per-channel tolerance, crops `inset` pixels inside it, and re-encodes (`libx264 -preset slow -crf 18 -pix_fmt yuv420p`, or VP9 for `.webm`), keeping audio. It never overwrites OUTPUT.

The crop is the largest even-sized rectangle inside the border; it is not forced to an exact 16:9. When the inner aspect is within 1% of 16:9 it prints `16:9 validation: ASPECT is within 1% of 16:9; crop WxH (dimensions made even, not exact 16:9)`; otherwise it warns and crops anyway. The detection algorithm is the installed one, unchanged; only that message (which used to claim "snapped to exact WxH") and the `--tolerance` help (which said `Default: 30` while the default is 60) were corrected.

## h asciinema

Casts are named `DIR/YYYYMMDDNNN.cast`, NNN counting from 000 within a day. `Hiiro::Cast#path(which, day:)` (lib/hiiro/cast.rb) is the one naming operation; `which` is a kind or an explicit index.

| Command | Prints / does |
|---------|---------------|
| `nname` | next index today (000 when the day has none) |
| `cname` / `lname` | highest index today (000 when none) |
| `pname` | highest index − 1 (never below 000) |
| `fname` | 000 |
| `name DAY [INDEX [LAST]]` | DAY is a relative day (`0`, `-7`, `+1`) or `YYYYMMDD`; INDEX defaults to that day's highest; prints INDEX..LAST |
| `record FILE...` | `asciinema rec NEXT -c "EDITOR... FILE..."` |
| `resume FILE...` | `asciinema rec NEXT -c "EDITOR... RESUME_ARGS... FILE..."` (a new cast; earlier casts are untouched) |
| `play [NAME] [ARGS...]` | `asciinema play NAME ARGS...`; NAME defaults to today's current cast |

After `record`, `resume`, and `play`, `reset` runs only when stdin and stdout are a terminal. The installed version also ran `reset` inside the recorded command; that is dropped (it asked for a terminal type when `TERM` was unknown, and the outer reset restores the terminal).

Profile section (portable defaults shown):

```yaml
casts:
  dir: ~/casts                 # previously hard-coded: ~/notes/yt/casts
  editor: $EDITOR or vi        # previously hard-coded: safe_nvim; a list is used as argv
  resume_args: ['+norm! g`"']  # vim: jump to the last cursor position
```

To keep the previous behavior:

```yaml
casts:
  dir: ~/notes/yt/casts
  editor: safe_nvim
```

asciinema 3.2.1 note: `play` can drop output recorded in the first ~15ms of a cast, and prints session output only to a terminal.
