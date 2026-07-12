# WindowKeeper Test Report — 2026-07-12

## Unit tests (swift test)
```
Test Suite 'ModelsAndStoreTests' passed at 2026-07-12 09:18:06.707.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.009 (0.010) seconds
Test Suite 'WindowKeeperPackageTests.xctest' passed at 2026-07-12 09:18:06.707.
	 Executed 29 tests, with 0 failures (0 unexpected) in 0.011 (0.013) seconds
Test Suite 'All tests' passed at 2026-07-12 09:18:06.707.
	 Executed 29 tests, with 0 failures (0 unexpected) in 0.011 (0.014) seconds
```

## End-to-end verification (live, ultra-wide 5120x1440 attached)

| Scenario | Expected | Observed | Result |
|----------|----------|----------|--------|
| `--diagnose` | trust status, config, 3 screens listed | Accessibility trusted: true; 9 zones; screens incl. 5120x1440 | PASS |
| Zone mode: TextEdit rule → left-half, launch TextEdit | window at AX (0, 30) 1280×1410 | x=0.0 y=30.0 w=1280.0 h=1410.0 | PASS |
| Remember mode: move window to (420,260) 900×700 | frame saved to frames.json after 1s debounce | frames.json contains exact frame | PASS |
| Remember mode: quit + relaunch TextEdit | window restored to saved frame | x=420.0 y=260.0 w=900.0 h=700.0 | PASS |
| App bundle | `make app` produces signed .app | com.saqibkamran.windowkeeper, arm64, ad-hoc signed, --version OK | PASS |

All test artifacts (test config, frames, /tmp files) were cleaned up after the run.
