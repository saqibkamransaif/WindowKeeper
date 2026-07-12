# WindowKeeper 1.1.0 Test Report — 2026-07-12

Root cause of reported bug: frames stored as absolute coordinates broke when the
display arrangement changed (2560 monitor removed; ultra-wide became primary).
The user's preset pointed at x=-5120 — coordinates that no longer existed.

## Unit tests
```
Test Suite 'All tests' passed at 2026-07-12 10:19:42.132.
	 Executed 40 tests, with 0 failures (0 unexpected) in 0.014 (0.017) seconds
```

## End-to-end (live, 2-display arrangement: ultra-wide primary + laptop)

| # | Scenario | Expected | Observed | Result |
|---|----------|----------|----------|--------|
| 1 | Save preset → move window to OTHER display → Apply (user's exact bug) | window returns to saved spot | (100,100) 896×709 restored exactly, cross-display | PASS |
| 2 | Apply stale v1.0 preset with dead coords (x=-5120) | graceful clamp onto visible display, honest log | landed (0,30) 1182×1347 inside ultra-wide; log 'placed 1' | PASS |
| 3 | Zone snap on new arrangement (TextEdit → left-half) | left half of ultra-wide | (0,30) 2560×1346 | PASS |
| 4 | User move re-captures in new format | frames.json gains displayUUID + rel offsets | uuid F1F9EFF4…, rel (300,120) | PASS |
| 5a | Preset apply overrides zone rule | window at preset frame, not zone | (3000,300) 1000×800 | PASS |
| 5b | Relaunch after 5a | zone rule applies again | (0,30) 2560×1346 (left-half) | PASS |

Cleanup: E2E presets deleted, user config restored, /tmp files removed.
Note: reinstall changed the ad-hoc signature — user must re-grant Accessibility once.
