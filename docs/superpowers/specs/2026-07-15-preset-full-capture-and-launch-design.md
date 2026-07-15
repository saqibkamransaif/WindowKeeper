# Presets: full capture of all open apps + one-click launch-and-restore

Date: 2026-07-15
Status: Approved (Approach A)

## Problem

Saving a preset only captured apps explicitly marked as *managed*; every other
app on screen was silently left out. Applying a preset only repositioned apps
that were already running; apps that weren't running were logged and skipped.
The user expectation: "save exactly what I see on all my screens, and one click
brings back the same apps in the same places."

## Decisions (confirmed with user)

1. **Save scope**: capture every regular app (`activationPolicy == .regular`)
   that has at least one standard window, on any display. Captured apps are
   **auto-added to the managed list** in Remember mode so WindowKeeper keeps
   watching them afterwards.
2. **Load behavior**: apps in the preset that aren't running are **launched
   automatically** and their windows placed once they appear. Running apps NOT
   in the preset are **left alone** (not hidden, not quit).

## Approach

Approach A — reuse the existing launch pipeline (chosen over a dedicated
`PresetRestorer` session object, which would duplicate the placement path for
marginal reporting benefit).

- `captureAllFrames()` iterates all regular running apps with a bundle ID
  (not just managed ones), skips apps with no standard windows, saves
  display-relative frames (existing `SavedFrame.displayUUID` mechanics keep
  multi-monitor placement exact), and upserts a Remember-mode rule + AX
  observer for any app not already ruled.
- `applyPreset(id:)` writes preset frames into `rememberedFrames` (existing),
  ensures every preset app has a rule (so the launch pipeline picks it up),
  places windows of running apps immediately (existing), and **launches**
  missing apps via `NSWorkspace.openApplication`. The existing
  `appDidLaunch → attach → applyRule` machinery places their windows from the
  remembered (= preset) frames. Uninstalled apps are logged.
- Running-but-windowless preset apps are re-opened (reopen event → window
  created → AX observer places it).
- `applyRule` window-wait retry ceiling extended from ~5s to ~15s so
  slow-launching apps still get placed.
- Menu copy updated: save dialog and capture summary say "all open apps"
  instead of "all managed apps".

## Testing

- Core layout math unchanged; existing 40-test suite must stay green
  (`swift test`).
- Live verification: save preset with mixed managed/unmanaged apps across
  displays; quit some apps; apply preset → apps relaunch and land on their
  saved frames on the correct displays.
