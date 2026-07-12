# Changelog

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
