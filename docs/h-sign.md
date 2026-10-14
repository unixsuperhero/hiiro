# h-sign

Inspect and verify the code signature of a macOS app bundle with `codesign`. It never signs, re-signs, or changes the bundle.

## Synopsis

```bash
h sign verify [APP]
h sign info [APP]
h sign requirement [APP]
h sign report [APP]
```

`APP` is a `.app` directory, default `release/CodeHiiro.app` relative to the current directory. A missing or non-`.app` path prints `h-sign: app bundle not found: APP` and exits 1.

| Subcommand | Runs | Exit status |
|------------|------|-------------|
| `verify` | `codesign --verify --deep --strict --verbose=2 APP` | `codesign`'s |
| `info` | `codesign -dv --verbose=4 APP` | `codesign`'s |
| `requirement` | `codesign -d -r- APP` | `codesign`'s |
| `report` | all three, then a summary (verification PASS/FAIL, bundle identifier, team identifier, signing authorities, designated requirement) and what must stay stable between releases | 0 only when all three succeed |
