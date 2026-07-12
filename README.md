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
- **Layout presets** — capture the whole current arrangement as a named preset;
  apply or update it any time from the menu.
- **Opt-in per app** — only apps you mark as *Managed* are touched.
- **Multi-display aware** — zones can target any connected display.

## Install

```bash
make install          # builds release, copies WindowKeeper.app to /Applications
```

Launch WindowKeeper, then grant **Accessibility** access when prompted
(System Settings → Privacy & Security → Accessibility). That permission is what
lets it read and move other apps' windows. Optionally add it to
System Settings → General → **Login Items** so it starts with your Mac.

## Use

Everything lives in the menu-bar icon:

| Menu item | What it does |
|-----------|--------------|
| Enabled | Master on/off switch |
| Capture Current Layout | Saves the frames of all managed apps right now |
| Presets → Save Current as New Preset… | Snapshot the current layout under a name |
| Presets → *name* → Apply / Update / Delete | Manage saved layouts |
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
