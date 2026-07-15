# Changelog

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
