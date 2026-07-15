# WindowKeeper — Design

## Problem
On an ultra-wide monitor, macOS does not reliably reopen app windows at the size and
position you left them. The user wants:

1. **Remember & restore** — for selected apps, remember window size/position and restore
   them automatically every time the app opens.
2. **Zones** — assign an app to a fixed screen region ("a special window for them");
   whenever that app opens, its windows snap to that region automatically.
3. **Presets** — capture the whole current layout (every open app, all displays)
   as a named preset, update it later, and restore it with one click: closed
   apps are relaunched and every window is placed back.
4. **App selection** — day-to-day management is opt-in per app; apps captured
   into a preset are opted in automatically.

## Architecture

Two SPM targets so all layout logic is unit-testable without the GUI or Accessibility:

```
WindowKeeperCore  (library — pure logic, no AppKit/AX dependency beyond CoreGraphics)
├── Models.swift        WindowFrame, PlacementMode, AppRule, Zone, LayoutPreset, Config
├── LayoutEngine.swift  coordinate math (Cocoa↔AX), zone resolution, frame matching
└── LayoutStore.swift   JSON persistence (atomic writes, injectable directory)

WindowKeeper      (executable — AppKit menu-bar app)
├── main.swift                 arg parsing (--diagnose, --version, --frames, --do) or GUI launch
├── AppDelegate.swift          NSStatusItem lifecycle
├── AccessibilityService.swift AXUIElement wrappers (windows, get/set frame, observers)
├── WindowManager.swift        orchestration: launch events → apply rules; moves → save
├── StatusMenuController.swift menu UI (enable, capture, presets, manage apps, zones)
└── Log.swift                  file logger → ~/Library/Application Support/WindowKeeper/logs
```

## Key decisions

- **Accessibility API (AXUIElement)** is the only sanctioned way to move other apps'
  windows on macOS. Requires the user to grant Accessibility permission once
  (System Settings → Privacy & Security → Accessibility).
- **Coordinates**: AX uses top-left origin (y down); NSScreen uses bottom-left (y up).
  All stored frames are in AX coordinates; `LayoutEngine` converts.
- **Zones are fractional** (0–1 of a display's visible frame) so the same zone definition
  works on any monitor, ultra-wide included. Built-in zones include halves, thirds and
  two-thirds — the useful set for a 21:9/32:9 screen.
- **Feedback-loop guard**: when WindowKeeper itself moves a window, move/resize
  notifications for that app are suppressed for a short window so we don't re-save
  frames we just applied.
- **Restore-on-launch retries**: apps create windows asynchronously after launch, so
  placement retries up to ~15 s until windows appear (preset-launched apps can be
  slow to show their first window).
- **Display-relative frames**: saved frames are stored relative to a display's
  hardware UUID (`SavedFrame`), so layouts survive monitor unplug/replug and
  primary-display changes; missing displays resolve to the main display, clamped
  on-screen. Legacy absolute-coordinate files migrate on decode.
- **Spaces limitation**: the AX API only exposes windows on currently visible
  Spaces; full-screen windows and windows on other Spaces cannot be captured.
- **Persistence**: three JSON files in `~/Library/Application Support/WindowKeeper/`:
  `config.json` (rules + zones + enabled flag), `frames.json` (last-known frames per
  bundle ID), `presets.json` (named layout snapshots). Atomic writes.

## Per-app placement modes

| Mode | Behavior |
|------|----------|
| `remember` | Last user-arranged frame(s) are saved (debounced 1 s after move/resize) and re-applied to windows on every launch, by window order. |
| `zone(id)` | Every window of the app is snapped to the zone's rect on launch and on new-window creation. |

## Presets

A preset is `{id, name, frames: [bundleID: [SavedFrame]]}` captured from every
regular running app with standard windows (not just managed apps); newly seen
apps get a Remember-mode rule so they stay managed. *Apply* overwrites
remembered frames, places windows of running apps, and **launches** preset apps
that aren't running — the normal launch pipeline then places their windows.
Running apps not in the preset are untouched. *Update* re-captures into an
existing preset.

The **magic button** is a prominent one-click "Restore *preset*" item at the
top of the status menu. It applies the preset selected via `config.magicPresetID`
("Use as Magic Button" per preset), falling back to the most recently saved.

## Testing

`WindowKeeperCore` is fully covered by XCTest: coordinate conversions, ultra-wide zone
math, frame tolerance matching, Codable round-trips, store persistence, preset
create/update/apply semantics, rule lookup. The AX/GUI layer is verified by building,
launching the binary, and a `--diagnose` mode that reports Accessibility trust status,
screen inventory, and config paths.
