# WindowKeeper — Design

## Problem
On an ultra-wide monitor, macOS does not reliably reopen app windows at the size and
position you left them. The user wants:

1. **Presets** — capture the whole current layout (every open app, all displays)
   as a named preset, update it later, and restore it with one click: closed
   apps are relaunched and every window is placed back.
2. **Passivity** — windows move ONLY on explicit user actions (save, apply,
   snap to zone). Nothing is repositioned or re-captured automatically; the
   user's day-to-day window juggling (e.g. switching between browser profile
   windows) must never trigger a placement. (Automatic remember-on-move and
   place-on-launch existed through 1.3.x and were removed in 1.4.0 — z-order
   changes made them shuffle look-alike windows.)
3. **Zones** — snap an app to a fixed screen region on demand.
4. **App selection** — management is opt-in per app; apps captured into a
   preset are opted in automatically.

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
├── AccessibilityService.swift AXUIElement wrappers (windows, get/set frame)
├── WindowManager.swift        orchestration: captures, restores, preset-launch placement
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
- **Identity + proximity window matching**: macOS lists an app's windows in
  z-order, so order-based frame assignment shuffles multi-window apps whenever
  a different window is focused. `LayoutEngine.assignTargets` matches windows
  to saved frames instead. Identity first: `SavedFrame` stores the capture-time
  window title, and the trailing " - " token (browsers put the profile name
  there) pairs each slot with its window wherever it is; known-different
  identities never cross. Then proximity: in-place windows keep their frame,
  the rest claim the closest free frame (center distance + size penalty), and
  windows beyond the saved count are left untouched.
- **Restore reconciliation is the only background activity**: `applyPreset`
  does a fast first pass (place running apps, launch the rest), then a
  reconciliation loop re-verifies the whole preset every 3 s for up to 2 min
  until every saved frame has a window on it: apps still not running are
  relaunched once, drifted windows are re-placed against current display
  geometry (a mid-restore arrangement change re-verifies everything), and apps
  with fewer windows than saved are asked for more via their own "New Window"
  menu item (AX press; requested only after the window count is stable across
  two passes, so slow starters restoring their own windows never get
  duplicates). Placements macOS overrides (row-snapped Terminal heights) are
  accepted rather than re-fought. `pendingPlacements` + `didLaunchApplication`
  remain as a fast path (60 s expiry, ~15 s window-appearance retry); the loop
  is the guarantee and ends with an honest log of anything still short.
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
| `remember` | Explicit captures (preset save/update, Capture Current Layout) store the app's frames; explicit restores re-apply them via proximity matching. |
| `zone(id)` | Selecting the zone snaps every current window of the app to the zone's rect; preset applies still restore captured frames. |

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
