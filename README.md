# WindowKeeper

A macOS menu-bar app that remembers where your app windows belong — built for
ultra-wide and multi-monitor setups. Save your whole desk as a preset, then
restore it with one click: closed apps relaunch and every window returns to
the exact size and place you left it, on every screen.

## Features

- **Layout presets** — capture every open app's exact window arrangement across
  all displays as a named preset. Applying it is a one-click restore: apps that
  aren't running are launched, and every window goes back to its saved place.
- **Magic button** — the preset you choose sits at the top of the menu as a
  bold "Restore …" item. Click the menu-bar icon, click the button, done.
- **Passive by design** — windows move ONLY when you ask (save, apply, snap to
  a zone). WindowKeeper never repositions anything on its own: no snapping
  when windows open, no re-capture when you drag something, no reshuffling
  when you switch between look-alike windows such as browser profiles.
- **Smart window matching** — multi-window apps (browsers with several
  profiles, editors with many documents) are restored by matching each window
  to its nearest saved frame, so restoring never swaps windows around; extra
  windows that were never captured are left where they are.
- **Zones** — snap an app to a screen region on demand (halves, thirds,
  two-thirds, center, maximize — the layouts that make an ultra-wide useful).
- **Multi-display aware** — frames are saved relative to their display and
  zones can target any connected display.

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

1. Open the apps you work with and arrange every window the way you like,
   on all your screens.
2. Click the window icon in the menu bar (there is no Dock icon) and choose
   **Presets → Save Current as New Preset…** — this snapshots every open app
   and auto-adds each one to the managed list.
3. That's it. The preset appears as the bold **✨ Restore …** button at the top
   of the menu; one click relaunches anything you've closed and puts every
   window back in its place. (With several presets, pick which one owns the
   button via **Presets → *name* → Use as Magic Button**.)
4. Optionally fine-tune per app under **Manage Apps**: keep
   **Remember Last Position** (default) or pick
   **Snap to Zone → Left Half / Middle Third / …** to pin it to a region.

## Use

Everything lives in the menu-bar icon:

| Menu item | What it does |
|-----------|--------------|
| ✨ Restore *preset* (top of menu) | One-click full restore of the magic preset |
| Enabled | Master on/off switch |
| Capture Current Layout | Saves the frames of every open app right now |
| Presets → Save Current as New Preset… | Snapshot every open app's layout under a name |
| Presets → *name* → Apply / Update / Delete | Apply launches missing apps and restores every window |
| Presets → *name* → Use as Magic Button | Make this preset the one-click restore at the top |
| Manage Apps → *app* → Managed | Opt an app in or out |
| Manage Apps → *app* → Remember Last Position | Restores use its captured frames (default) |
| Manage Apps → *app* → Snap to Zone → *zone* | Snap the app to a screen region now |

Config lives in `~/Library/Application Support/WindowKeeper/` as three JSON
files (`config.json`, `frames.json`, `presets.json`); logs in `logs/` next to
them.

## Limitations

- **Full-screen windows and windows on other Spaces can't be captured.** The
  Accessibility API only exposes windows on the currently visible Spaces —
  bring windows to a normal desktop before saving a preset.
- **Changing the code signature resets the Accessibility grant.** The build
  signs with your first Apple Development / Developer ID identity when one
  exists (stable across rebuilds) and falls back to ad-hoc signing otherwise —
  ad-hoc builds need the grant re-added after every `make install`. After any
  re-grant, relaunch WindowKeeper; some apps (Electron ones especially) keep
  refusing a client that started before the grant.
- **Window contents aren't restored** — WindowKeeper restores which apps are
  open and where their windows sit; tabs/documents are each app's own
  session-restore behavior.

## Development

```bash
make build      # debug build
make test       # run the unit test suite (WindowKeeperCore)
make diagnose   # print accessibility status, config, and screen inventory
make run        # run the debug binary in the foreground
```

Architecture and design decisions: [docs/DESIGN.md](docs/DESIGN.md).
