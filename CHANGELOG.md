# Changelog

## [1.6.0] — 2026-07-16

### Added
- **Restores now reconcile until every saved window is open and in place.**
  Applying a preset was a single fire-and-forget pass that relied on macOS
  launch notifications; after a reboot this routinely left holes — an app
  whose notification never arrived was never placed, a second Terminal window
  was never recreated, and windows placed while displays were still waking up
  ended a menu-bar-height off once the arrangement settled. A reconciliation
  loop now re-verifies the whole preset every 3 s for up to 2 minutes after
  an apply: apps that still aren't running are relaunched once, drifted
  windows are re-placed against the *current* display geometry, and apps with
  fewer windows than the preset saved are asked for more via their own
  "New Window" menu item (pressed through Accessibility — no fake keystrokes,
  so it can never hit the wrong app). Window creation waits for the app's
  window count to hold steady across two passes so slow starters (Slack,
  Electron apps) restoring their own windows are never handed duplicates.
  Apps verified in place are left alone for the rest of the restore — unless
  the display arrangement changes, which re-verifies everything. The loop
  ends with an honest log line: everything placed, or exactly what is still
  short and why.

## [1.5.0] — 2026-07-15

### Added
- **Title-aware window matching.** Captures now store each window's title, and
  restores match saved frames to live windows by the title's trailing " - "
  token first — which is where browsers put the profile name (e.g.
  "Perplexity - Comet - Saqib Kamran" → "Saqib Kamran"). A specific browser
  profile can therefore own a specific spot: it returns there no matter where
  it was dragged, while other profile windows keep their own frames or, if
  they were never captured, are left alone. A titled slot never grabs a window
  that clearly belongs to a different identity; windows and slots without a
  recognizable title fall back to plain proximity matching, so apps with
  volatile titles behave exactly as in 1.4.0. Older preset/frame files (no
  titles) load unchanged.

## [1.4.0] — 2026-07-15

### Changed
- **WindowKeeper is now fully passive: windows move only on explicit actions.**
  Automatic behaviors are gone — no more snapping a window when it opens, no
  auto-recapture when you drag or resize, no bulk re-apply when the display
  arrangement changes. Frames are captured when you save/update a preset (or
  Capture Current Layout) and applied when you restore one or snap an app to a
  zone. The only background trigger left is finishing an explicit restore:
  apps a preset just launched get their windows placed once they appear
  (ignored for launches you perform yourself).
- **Restores match windows to saved frames by proximity, not list order.**
  macOS reports windows front-to-back, so with several look-alike windows
  (e.g. multiple browser profiles) merely focusing a different window used to
  remap every saved frame and shuffle the whole set. Windows already sitting
  on a saved frame now keep it, moved windows return to their nearest saved
  frame, and extra windows with no saved slot are left where they are
  (previously they were stacked onto the last saved frame).

### Removed
- Per-app AX observers (window created/moved/resized) — no longer needed in
  the passive model.

## [1.3.1] — 2026-07-15

### Fixed
- **"Update from Current Layout" no longer silently drops apps it can't see.**
  Capturing goes through the Accessibility API, which cannot see windows on
  another macOS Space (or minimized/hidden ones). Updating a preset while an
  app's only window sat on a different Space removed that app from the preset
  entirely — so a later "Restore" left its window untouched, which read as
  "restore doesn't put everything back". Now an app that is still running but
  has no capturable windows keeps its existing preset entry (apps that were
  quit are still removed on update, as before). The log reports which entries
  were kept.
- **Accessibility grant no longer breaks on every rebuild.** The app was
  ad-hoc signed, so each build produced a new code signature and macOS
  silently revoked the Accessibility permission (all AX calls then fail with
  `kAXErrorAPIDisabled`, which looks like "restore does nothing").
  `make-app.sh` now signs with the first available Apple Development /
  Developer ID identity, whose stable code requirement keeps the TCC grant
  valid across builds; it falls back to ad-hoc when no identity exists. One
  manual re-grant is needed after installing this version.
- Failed AX window queries are now logged with the AX error code instead of
  silently returning an empty window list.

## [1.3.0] — 2026-07-15

### Added
- **Magic button.** A bold, accent-tinted "Restore *preset*" item now sits at
  the very top of the menu-bar menu — one click launches every app in the
  preset and puts every window back in its saved place on all displays. The
  target preset is the explicitly chosen one (Presets → *name* → "Use as
  Magic Button", persisted as `magicPresetID` in config.json), falling back
  to the most recently saved preset.

### Notes
- Windows that live on another macOS Space (or are full-screen) are invisible
  to the Accessibility API and can't be captured — bring them to a visible
  desktop before saving a preset.

## [1.2.0] — 2026-07-15

### Changed
- **Presets now capture every open app, not just managed ones.** Saving or
  updating a preset (and "Capture Current Layout") snapshots the exact window
  frames of every regular app with open windows, on all displays. Newly
  captured apps are auto-added to the managed list (Remember mode) so
  WindowKeeper keeps watching them afterwards.
- **Applying a preset is a one-click full restore.** Apps in the preset that
  aren't running are launched automatically and their windows placed on the
  saved display/position as soon as they appear (window-wait extended from
  ~5 s to ~15 s for slow launchers). Apps missing a rule get one on the fly,
  so old presets restore too. Running apps NOT in the preset are left alone;
  apps no longer installed are logged as such.

## [1.1.0] — 2026-07-12

### Fixed
- **Preset apply / restore broke after display arrangement changes** (the
  "apply did nothing" bug). Frames were stored as absolute screen coordinates;
  when a monitor was unplugged or the primary display changed, saved
  coordinates pointed at space that no longer existed and macOS silently
  clamped or ignored placements. Frames are now stored **relative to a
  specific display (hardware UUID)** and resolve against the current
  arrangement: exact position if the display is present, main-display
  fallback if not, always clamped fully on-screen. Legacy v1.0 files migrate
  automatically.
- **Placement is now verified.** AX set calls report success even when macOS
  clamps the window; WindowKeeper now reads the frame back, retries, and logs
  honestly (`placed / adjusted / failed / skipped` per app).
- **Applying a preset now overrides zone rules** — an explicit Apply places
  the captured frames; zone rules re-apply on the next launch.

### Added
- **Display-change reactivity**: when the arrangement changes (monitor
  plugged/unplugged/asleep), managed apps are automatically put back in place
  after things settle.
- **Capture feedback**: saving/updating a preset shows exactly which apps were
  captured and which managed apps were missed because they weren't running —
  previously a silent thin preset looked like a broken Apply.
- **Scriptable commands**: `WindowKeeper --do "capture"`,
  `--do "apply-preset:<name>"`, `--do "save-preset:<name>"` talk to the
  running app (also used by the automated E2E suite).
- 11 new unit tests (40 total): display-relative resolution, arrangement-change
  regression, legacy migration, clamping.

## [1.0.0] — 2026-07-12

### Added
- Initial release of WindowKeeper, a menu-bar window manager for ultra-wide screens.
- **Remember mode**: managed apps' window frames are saved (debounced) on every
  move/resize and restored automatically on the next launch.
- **Zone mode**: per-app assignment to fractional screen zones (halves, thirds,
  two-thirds, center, maximize) with multi-display support; windows snap on
  launch and on new-window creation.
- **Layout presets**: save the current arrangement under a name, apply, update
  from current layout, and delete — all from the menu bar.
- **Per-app opt-in** via Manage Apps menu; only selected apps are touched.
- Tolerant config decoding: partial/hand-edited `config.json` falls back to
  defaults per field instead of resetting.
- CLI diagnostics: `--version`, `--diagnose` (accessibility status, config,
  screens), `--frames <bundle-id>` (live window frames of a running app).
- `make install` builds a signed `WindowKeeper.app` bundle into `/Applications`.
- Unit test suite: 29 tests covering coordinate math (Cocoa↔AX), ultra-wide
  zone resolution, frame tolerance matching, Codable round-trips, store
  persistence, and placement planning.

### Verified
- End-to-end on a live ultra-wide setup: zone snap on launch (left-half,
  exact frame), remember-save on user move (debounced to `frames.json`), and
  restore on relaunch (exact frame) — see `tests/reports/`.

### TODO / future ideas
- Reload config automatically when `config.json` is edited by hand (currently
  read at launch; the menu is the live mutation path).
- Custom user-defined zones from the menu (today: JSON-editable, built-ins in menu).
- Per-display remembered layouts keyed by display arrangement (e.g. laptop
  undocked vs. docked to the ultra-wide).
- Optional window-title matching for multi-window apps instead of window order.
