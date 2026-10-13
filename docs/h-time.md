# h-date / h-time

Convert, format, and measure points in time. `h date` and `h time` are one set
of registrations (`Hiiro::TimeCommands`) over `Hiiro::TimeInput` and
`Hiiro::Duration`; they differ only in how a point and `now` print.

| Subcommand (aliases) | Options | `h date` prints | `h time` prints |
|---|---|---|---|
| `to_unix` (`unix`, `ts`) `[TEXT]` | `-m/--ms` | unix seconds (ms with `-m`); no text means now | same |
| `from_unix` (`parse`) `TIMESTAMP` | `-m/--ms`, `-u/--utc` | ISO 8601 with milliseconds, `1970-01-01T00:00:00.000Z` | `HH:MM:SS.mmm`, `00:00:00.000` |
| `fmt` (`format`, `strftime`) `CHARS` | `-u/--utc` | now through strftime with `%` before each letter (`Y-m-d` → `%Y-%m-%d`; a literal `%` stays) | same |
| `now` | date: `-u`; time: `-m`, `-u` | ISO 8601 without fraction | `HH:MM:SS` (`HH:MM:SS.mmm` with `-m`) |
| `dur` (`duration`, `human`) `SECONDS` | `-m/--ms` | `1d1h1m1s`, `0s`, `-1m1s` (rationals such as `1/3` accepted; rounded to whole seconds) | same |
| `diff A B` | `-m/--ms` | B minus A: `h date diff 120 0` → `-2m` | same |

Input rules (`TimeInput.parse`): digits are unix seconds, or milliseconds when
the integer part is longer than 11 digits or `--ms` is given; a decimal or
negative number is accepted; blank or `now` is the current time; anything else
goes through `Time.parse`. Without `--utc` a point prints in the local zone
(`TZ`). A missing argument prints the subcommand's usage on stderr and exits 1,
for example `usage: h time diff <time-a> <time-b>  (each: time string or unix timestamp)`.
