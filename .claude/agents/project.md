# WindowKeeper — Project Agent

## Stack
- Swift 6 toolchain, Swift Package Manager (no Xcode project)
- macOS 13+ target, AppKit menu-bar app (`NSStatusItem`, no Dock icon)
- Accessibility API (`AXUIElement`) for reading/moving other apps' windows
- No Laravel/React here — global web-stack rules do not apply

## Layout
- `Sources/WindowKeeperCore` — pure logic (models, coordinate math, JSON store).
  Everything here must stay AppKit-free and unit-tested.
- `Sources/WindowKeeper` — executable: AX wrappers, window manager, menu UI.
- `Tests/WindowKeeperCoreTests` — XCTest suite; run with `swift test`.

## Rules
- All layout/placement math goes in `WindowKeeperCore` with tests — never
  inline in the app target.
- Stored frames are always in AX coordinates (top-left origin).
- When WindowKeeper sets a frame itself, suppress move/resize capture for that
  bundle ID (see `WindowManager.suppress`) to avoid feedback loops.
- User config lives in `~/Library/Application Support/WindowKeeper/`; never
  commit or overwrite it in tests — tests use temp directories.
- Verification requires a live run: `make diagnose`, then the E2E flow in
  `tests/reports/` (zone snap + remember/restore with a real app like TextEdit).

## Build & release
- `make test` → unit suite; `make app` → signed bundle in `dist/`;
  `make install` → `/Applications` (needs no approval, local machine only).
- Bundle ID: `com.saqibkamran.windowkeeper`. Ad-hoc signed; if the binary is
  rebuilt, macOS may re-prompt for Accessibility — that is expected.

## GitHub account
- This repo lives on the personal account: `saqibkamransaif/WindowKeeper`.
- If `gh` has multiple accounts authenticated, switch to `saqibkamransaif`
  before `git push` or `gh` operations on this repo
  (`gh auth switch -h github.com -u saqibkamransaif`), and switch back after.
