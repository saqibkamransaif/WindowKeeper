# Test report: WindowKeeper 1.9.0 (2026-11-17 4:20 AM PT)

## Unit tests
`swift test`: 69 tests, 0 failures (6 new in PresetCatalogTests: default
layout choice, rename, blank-name handling; written first, failed, then pass).

## Live app (installed /Applications/WindowKeeper.app, 1.9.0)
Data backed up first and restored after; restored files byte-identical.
- Menu read through Accessibility: Restore My Setup (⌘R), Remember Current
  Layout, Send Focused Window Back (⌥⌘R), Preferences… (⌘,), Quit.
- ⌥⌘R pressed with Terminal in front: log "Send-back: returning focused
  Terminal window to its place in 'My Setup'".
- Preferences opened from the menu; Layouts, Apps and General tabs
  screenshotted and checked. On/off switch reads 1 (on).
- Apps tab: remove on System Settings (not running) removed only that rule
  from config.json; Terminal kept.
