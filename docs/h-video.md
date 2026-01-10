# h-video

FFmpeg wrapper for common video operations.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h video <subcommand> <input_file> [args...]
```

## Requirements

- FFmpeg and FFprobe must be installed

## Subcommands

### Info / Inspection

| Command | Description |
|---------|-------------|
| `info <file>` | Human-readable video summary |
| `streams <file>` | List all streams (video, audio, subs) |
| `duration <file>` | Get video duration |
| `metadata <file>` | Show metadata as JSON |
| `list_subs <file>` | List subtitle tracks |
| `help` | Show full command reference |

### Resizing

| Command | Description |
|---------|-------------|
| `resize <file> [height] [out]` | Resize to height (default 720) |
| `resize720 <file> [out]` | Resize to 720p |
| `resize1080 <file> [out]` | Resize to 1080p |

### Format Conversion

| Command | Description |
|---------|-------------|
| `convert <file> <format> [out]` | Convert to format (mp4, mkv, webm, etc.) |
| `to_mp4 <file> [out]` | Convert to MP4 (H.264/AAC) |
| `to_webm <file> [out]` | Convert to WebM (VP9/Opus) |
| `to_mkv <file> [out]` | Remux to MKV container |

### Audio Extraction

| Command | Description |
|---------|-------------|
| `audio <file> [out]` | Extract audio as MP3 |
| `audio_wav <file> [out]` | Extract audio as WAV |
| `audio_aac <file> [out]` | Extract audio as AAC |
| `audio_flac <file> [out]` | Extract audio as FLAC |
| `mute <file> [out]` | Remove audio track |
| `replace_audio <video> <audio> [out]` | Replace audio track |
| `volume <file> <level> [out]` | Adjust volume (2.0 = 2x, 0.5 = half) |

### Clipping

| Command | Description |
|---------|-------------|
| `clip <file> <start> <duration> [out]` | Extract clip by duration |
| `clip_to <file> <start> <end> [out]` | Extract clip by end time |
| `clip_precise <file> <start> <dur> [out]` | Re-encoded clip (more accurate) |

### Subtitles

| Command | Description |
|---------|-------------|
| `subs <file> [stream_idx] [out]` | Extract subtitle track (default: first) |
| `subs_all <file>` | Extract all subtitle tracks |

### Images / Thumbnails

| Command | Description |
|---------|-------------|
| `thumbnail <file> [time] [out]` | Extract single frame |
| `thumbnails <file> [interval] [pattern]` | Extract frames every N seconds |

### GIF Creation

| Command | Description |
|---------|-------------|
| `gif <file> [start] [duration] [out]` | Create GIF (standard quality) |
| `gif_hq <file> [start] [duration] [out]` | Create high-quality GIF |

### Transformation

| Command | Description |
|---------|-------------|
| `speed <file> <factor> [out]` | Change speed (2.0 = 2x faster) |
| `rotate <file> [dir] [out]` | Rotate (cw, ccw, 180) |
| `flip_h <file> [out]` | Flip horizontally |
| `flip_v <file> [out]` | Flip vertically |
| `crop <file> <w:h:x:y> [out]` | Crop video |
| `fps <file> <rate> [out]` | Change frame rate |

### Compression

| Command | Description |
|---------|-------------|
| `compress <file> [crf] [out]` | Compress (crf: 18-28, higher = smaller) |
| `compress_small <file> [out]` | Aggressive compression + 480p |

### Other

| Command | Description |
|---------|-------------|
| `concat <file1> <file2> ... <out>` | Join multiple videos |
| `strip_metadata <file> [out]` | Remove all metadata |

## Examples

```sh
# Get video info
h video info movie.mp4

# Resize to 720p
h video resize720 movie.mp4

# Convert MKV to MP4
h video to_mp4 movie.mkv

# Extract 60 seconds starting at 1:30
h video clip movie.mp4 00:01:30 60

# Extract clip from 1:30 to 2:30
h video clip_to movie.mp4 00:01:30 00:02:30

# Create a GIF from the first 10 seconds
h video gif movie.mp4 00:00:00 10

# Extract audio as MP3
h video audio movie.mp4

# Double the playback speed
h video speed movie.mp4 2.0

# Rotate 90 degrees clockwise
h video rotate movie.mp4 cw

# Compress with CRF 28 (more compression)
h video compress movie.mp4 28

# Concatenate videos
h video concat part1.mp4 part2.mp4 part3.mp4 output.mp4

# Extract thumbnail at 30 seconds
h video thumbnail movie.mp4 00:00:30
```

## Time Format

Time can be specified as:
- `HH:MM:SS` (e.g., `01:30:00` for 1 hour 30 minutes)
- `MM:SS` (e.g., `05:30` for 5 minutes 30 seconds)
- Seconds (e.g., `90` for 1 minute 30 seconds)

## Output Files

If no output file is specified, files are automatically named based on the operation:
- `movie.720p.mp4` for resize operations
- `movie.clip_00-01-30.mp4` for clip operations
- `movie.audio.mp3` for audio extraction
- etc.

## Notes

- All commands pass through to FFmpeg
- The `clip` commands use stream copy (`-c copy`) for speed; use `clip_precise` for frame-accurate cuts
- GIF operations use palette generation for better quality
