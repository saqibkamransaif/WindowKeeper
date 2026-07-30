# Send It Back (⌥⌘O) — Design

**Date:** 2026-07-30
**Status:** Approved

## Problem

While working, you enlarge the focused app's window to concentrate on it. When
you switch tasks, that window is out of place. Restoring the whole preset is
overkill — you want one keystroke that puts *just the window you're using*
back to its organized spot, leaving everything else untouched.

## Decisions (made with the user)

| Question | Decision |
|----------|----------|
| Where does "its place" come from? | The **magic-button preset** — same source as the full Restore. No background tracking of manual resizes (keeps the passive-by-design rule). |
| Trigger | **Global hotkey ⌥⌘O** ("O for original position") plus a menu-bar item showing the shortcut. Plain ⌘O was rejected because it would hijack "Open file" system-wide. |
| Scope for multi-window apps | **Only the focused window** moves. The app's other windows stay where they are. |

## Behavior

1. User presses ⌥⌘O (or clicks **Send Focused Window Back** in the menu).
2. WindowKeeper identifies the frontmost app and its focused window.
3. It loads the magic preset's saved frames for that app's bundle ID and runs
   the existing smart matching (`assignedTargets`) across the app's current
   windows, so each window is paired with the right saved frame (browser
   profiles return to their own spots).
4. Only the frame assigned to the *focused* window is applied, using the
   existing `setFrame` placement with clamp verification.
5. Nothing else moves — not the app's other windows, not other apps.

### Failure handling (quiet by design)

Any of these produce a system beep + a log line, never a dialog:

- No magic preset is set.
- The frontmost app has no entry in the magic preset ("no saved place for X
  in preset 'Y'").
- No focused window can be resolved (e.g. frontmost app has no windows).
- Matching yields no target frame for the focused window.
- WindowKeeper is disabled via its Enabled toggle → the action is a no-op
  (beep + log), consistent with the rest of the app.

## Components

| Unit | Change |
|------|--------|
| `HotkeyService` (new, `Sources/WindowKeeper/`) | Thin wrapper around Carbon `RegisterEventHotKey`. Registers ⌥⌘O at launch, invokes a callback. No new permissions; consumes the keystroke. Shortcut lives in one constant for future configurability. |
| `AccessibilityService` | Add `focusedWindow(pid:)` reading `kAXFocusedWindowAttribute`. |
| `WindowManager` | Add `sendFocusedWindowBack()`: frontmost app → focused window → magic preset frames → `assignedTargets` → apply only the focused window's target. |
| `StatusMenuController` | Add "Send Focused Window Back" item (keyEquivalent ⌥⌘O for display) under the magic Restore button. |
| `AppDelegate`/`main` | Instantiate `HotkeyService`, wire callback to `WindowManager.sendFocusedWindowBack()`. |

## Out of scope (YAGNI)

- Background tracking / "undo my last resize".
- Configurable shortcut UI (constant only).
- Per-app hotkeys.
- Restoring all windows of the app (explicitly rejected — focused window only).

## Testing

- Core matching logic is already covered by `LayoutEngine` tests; the new
  selection ("which target belongs to the focused window") is exercised via a
  unit test in `WindowKeeperCore` if the selection helper lands there.
- Manual verification: enlarge a preset app's window → ⌥⌘O returns it; second
  Chrome window stays put; app not in preset → beep + log; ⌘O still opens
  files normally in other apps.
