# h-encode / h-decode

Byte filters over one codec table (`Hiiro::Codec`): the same formats, aliases,
input reader, and arity check for both directions.

```sh
h encode <format> [file]
h decode <format> [file]
```

| Format (aliases) | Encode | Decode |
|---|---|---|
| `base64` (`b64`) | standard Base64 | whitespace and padding optional |
| `base64url` (`b64url`) | URL-safe Base64 **without padding** | whitespace and padding optional |
| `hex` (`base16`, `b16`) | lowercase hexadecimal | hexadecimal, even number of digits |
| `uri` (`url`, `percent`) | RFC 3986 component: everything except `A-Za-z0-9._~-` becomes `%XX` | `%XX` only; `+` stays `+` |
| `form` (`query`) | `application/x-www-form-urlencoded` (space → `+`); input must be UTF-8 | `+` becomes a space |
| `html` (`html-entities`) | HTML entities; input must be UTF-8 | entities to text |
| `json` (`json-string`) | a JSON string literal; input must be UTF-8 | only a JSON **string** is accepted |
| `rot13` | ROT13 (self-inverse) | same |

`help` and no format print the usage.

Input: a named file, else `-` (explicit stdin), else piped stdin, else the
macOS clipboard through `pbpaste` (an empty clipboard is empty input). Bytes are
read and written in binary, so NUL and non-UTF-8 bytes round-trip through
`base64`, `base64url`, `hex`, `uri`, and `rot13`. Nothing adds a newline.

Failures print one line on stderr, write nothing on stdout, and exit 1:
`File not found: PATH`, `Expected at most one input file.`,
`JSON encoding requires valid UTF-8 input.`, and
`Decode failed: malformed percent escape` (also for `%zz`, `%4`, invalid
Base64/hex, and non-string JSON).
