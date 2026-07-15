# WindowKeeper

A macOS menu-bar app that remembers where your app windows belong — built for
ultra-wide monitors. Pick which apps it manages; every time one of them opens,
its windows go back to the exact size and place you left them, or snap to a
zone you assigned.

## Features

- **Remember & restore** — managed apps reopen at their last size/position,
  saved automatically whenever you move or resize a window.
- **Zones** — assign an app to a screen region (halves, thirds, two-thirds,
  center, maximize — the layouts that make an ultra-wide useful). Every new
  window of that app snaps there automatically.
- **Layout presets** — capture every open app's exact window arrangement across
  all displays as a named preset. Applying it is a one-click restore: apps that
  aren't running are launched, and every window goes back to its saved place.
- **Opt-in per app** — day-to-day, only apps you mark as *Managed* are touched
  (apps captured into a preset become managed automatically).
- **Multi-display aware** — zones can target any connected display.

## Install

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/saqibkamransaif/WindowKeeper.git
cd WindowKeeper
make install          # builds release, copies WindowKeeper.app to /Applications
open /Applications/WindowKeeper.app
```

On first launch, grant **Accessibility** access when prompted
(System Settings → Privacy & Security → Accessibility → enable WindowKeeper),
then quit and relaunch the app once. That permission is what lets it read and
move other apps' windows — without it the app runs but can't manage anything.

Optionally add it to System Settings → General → **Login Items** so it starts
with your Mac.

## First-time setup

1. Click the window icon in the menu bar (there is no Dock icon).
2. **Manage Apps → [pick an app] → Managed** — opt the app in.
3. Choose its behavior: leave **Remember Last Position** on (default — it
   saves wherever you drag the window and restores it on next launch), or pick
   **Snap to Zone → Left Half / Middle Third / …** to pin it to a region.
4. Arrange everything the way you like, then
   **Presets → Save Current as New Preset…** to snapshot the whole layout.

## Use

Everything lives in the menu-bar icon:

| Menu item | What it does |
|-----------|--------------|
| ✨ Restore *preset* (top of menu) | One-click full restore of the magic preset |
| Enabled | Master on/off switch |
| Capture Current Layout | Saves the frames of every open app right now |
| Presets → Save Current as New Preset… | Snapshot every open app's layout under a name |
| Presets → *name* → Apply / Update / Delete | Apply launches missing apps and restores every window |
| Manage Apps → *app* → Managed | Opt an app in or out |
| Manage Apps → *app* → Remember Last Position | Restore where you last put it (default) |
| Manage Apps → *app* → Snap to Zone → *zone* | Pin the app to a screen region |

Config lives in `~/Library/Application Support/WindowKeeper/` as three JSON
files (`config.json`, `frames.json`, `presets.json`); logs in `logs/` next to
them.

## Development

```bash
make build      # debug build
make test       # run the unit test suite (WindowKeeperCore)
make diagnose   # print accessibility status, config, and screen inventory
make run        # run the debug binary in the foreground
```

Architecture and design decisions: [docs/DESIGN.md](docs/DESIGN.md).
