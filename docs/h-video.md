# h video and h audio

`h video` wraps `ffmpeg` / `ffprobe` for common video operations. `h audio` adds audio clipping, duration sums, and a transcription adapter. Both need `ffmpeg` and `ffprobe` on `PATH`.

## Preset verbs

Every verb with the shape "one input, a few positional parameters, fixed ffmpeg output arguments, default output named after the input" is one row of `Hiiro::Media::PRESETS` (lib/hiiro/media.rb). Each row runs:

```text
ffmpeg -i INPUT ARGS... OUTPUT
OUTPUT defaults to Hiiro::Media.output_name(INPUT, SUFFIX, EXT) = "BASENAME.SUFFIX.EXT" in the current directory
```

```js
// one row of the table
{ name: "clip_to",
  params: [{ name: "start", label: "start_time (e.g., 00:01:30 or 90)", time: true },
           { name: "end",   label: "end_time (e.g., 00:02:30 or 150)", time: true }],
  args: ["-ss", "%{start}", "-to", "%{end}", "-c", "copy"],
  suffix: "clip_%{start}_to_%{end}",   // time params appear with ':' -> '-'
  ext: null }                          // null keeps the input extension

// h video clip_to in.mp4 00:00:01 3
// => ffmpeg -i in.mp4 -ss 00:00:01 -to 3 -c copy in.clip_00-00-01_to_3.mp4
```

| Verb | Arguments | ffmpeg output arguments | Default output |
|------|-----------|-------------------------|----------------|
| `resize` | FILE [HEIGHT=720] [OUT] | `-vf scale=-2:HEIGHT` | `B.HEIGHTp.EXT` |
| `resize720` / `resize1080` | FILE [OUT] | `-vf scale=-2:720` / `scale=-2:1080` | `B.720p.EXT` / `B.1080p.EXT` |
| `convert` | FILE FORMAT [OUT] | (none; ffmpeg picks codecs) | `B.converted.FORMAT` |
| `to_mp4` | FILE [OUT] | `-c:v libx264 -c:a aac` | `B.converted.mp4` |
| `to_webm` | FILE [OUT] | `-c:v libvpx-vp9 -c:a libopus` | `B.converted.webm` |
| `to_mkv` | FILE [OUT] | `-c copy` (remux) | `B.converted.mkv` |
| `audio` | FILE [OUT] | `-vn -acodec libmp3lame -q:a 2` | `B.audio.mp3` |
| `audio_wav` | FILE [OUT] | `-vn` | `B.audio.wav` |
| `audio_aac` | FILE [OUT] | `-vn -c:a aac -b:a 192k` | `B.audio.aac` |
| `audio_flac` | FILE [OUT] | `-vn -c:a flac` | `B.audio.flac` |
| `clip` | FILE START DURATION [OUT] | `-ss START -t DURATION -c copy` | `B.clip_START.EXT` |
| `clip_to` | FILE START END [OUT] | `-ss START -to END -c copy` | `B.clip_START_to_END.EXT` |
| `clip_precise` | FILE START DURATION [OUT] | `-ss START -t DURATION` (re-encode) | `B.clip_precise_START.EXT` |
| `subs` | FILE [INDEX=0] [OUT] | `-map 0:s:INDEX` | `B.subs_INDEX.srt` |
| `thumbnail` | FILE [TIME=00:00:01] [OUT] | `-ss TIME -vframes 1` | `B.thumb_TIME.jpg` |
| `mute` | FILE [OUT] | `-c:v copy -an` | `B.muted.EXT` |
| `volume` | FILE LEVEL [OUT] | `-filter:a volume=LEVEL -c:v copy` | `B.vol_LEVEL.EXT` |
| `compress` | FILE [CRF=28] [OUT] | `-c:v libx264 -crf CRF -preset medium -c:a aac -b:a 128k` | `B.compressed_crfCRF.EXT` |
| `compress_small` | FILE [OUT] | `-c:v libx264 -crf 32 -preset slower -c:a aac -b:a 96k -vf scale=-2:480` | `B.small.EXT` |
| `flip_h` / `flip_v` | FILE [OUT] | `-vf hflip` / `-vf vflip`, `-c:a copy` | `B.flipped_h.EXT` / `B.flipped_v.EXT` |
| `crop` | FILE W:H:X:Y [OUT] | `-vf crop=W:H:X:Y` | `B.cropped.EXT` |
| `fps` | FILE RATE [OUT] | `-filter:v fps=RATE` | `B.RATEfps.EXT` |
| `strip_metadata` | FILE [OUT] | `-map_metadata -1 -c copy` | `B.clean.EXT` |

All clip verbs seek after `-i` (output seeking). `clip` and `clip_to` copy streams, so a cut starts at the keyframe at or before START; when no keyframe falls inside the range the copied clip has no video packets. `clip_precise` re-encodes and starts exactly at START.

A missing required argument fails with `ERROR: Missing required argument: LABEL` and exit 1.

## Other verbs

These have their own shapes and stay as separate handlers: `info`, `streams`, `duration`, `metadata`, `list_subs` (probes, no output file); `subs_all`, `thumbnails` (pattern outputs); `gif` (`fps=10,scale=480:-1`) and `gif_hq` (two-pass palette, `fps=15,scale=640:-1`); `replace_audio` (two inputs); `concat` (many inputs, last argument is the output); `speed` (derived `setpts`/`atempo`); `rotate` (direction to `transpose`). `h video help` prints the full list.

## h audio

- `h audio clips FILE T0 T1 T2 ...` cuts consecutive ranges with the `clip_to` preset in-process: `clip_000.wav` is T0..T1, `clip_001.wav` is T1..T2, and so on.
- `h audio length FILE...` prints `File: FILE => SECONDS` (two decimals) per readable file and then the sum as `{:sum=>TOTAL}`. Files ffprobe cannot read print `FILE: no duration` on stderr and are not summed. `encapsulated_length`, `cls_proc_length`, and `inl_proc_length` are aliases.
- `h audio transcribe [-t] [-s] [-j] FILE` (alias `xscribe`) runs the configured transcriber: `COMMAND... FILE --model MODEL -f FORMATS`, where FORMATS is the selected `txt,srt,json` or `all`. The command and model are read only when this verb runs, from the `transcribe` profile section:

```yaml
# ~/.config/hiiro/profile.yml
transcribe:
  command: ~/proj/vc/VoxCPM/.venv/bin/mlx_whisper   # default: mlx_whisper (on PATH); a list is used as argv
  model: mlx-community/whisper-large-v3-turbo        # default: $WHISPER_MODEL
```

A command that is not found or an unset model is an error naming the profile key. The installed experiments `map` and `times` (debugger bodies over a literal `rant.json`) are not ported.
