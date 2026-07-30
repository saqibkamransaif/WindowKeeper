# Send It Back (⌥⌘O) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A global ⌥⌘O hotkey (plus a menu item) that moves ONLY the focused window of the frontmost app back to its saved place in the magic-button preset.

**Architecture:** A new `HotkeyService` (Carbon `RegisterEventHotKey`) fires a callback into a new `WindowManager.sendFocusedWindowBack()`, which resolves the frontmost app's focused window via a new `AccessibilityService.focusedWindow(pid:)`, runs the existing `LayoutEngine.assignTargets` matching over the app's windows against the magic preset's saved frames, and applies only the frame assigned to the focused window. Failures beep + log, never dialog.

**Tech Stack:** Swift 5.9 SPM package, AppKit, ApplicationServices (AX), Carbon.HIToolbox. macOS 13+.

## Global Constraints

- Passive by design: windows move ONLY on explicit user action. This feature moves exactly one window, on hotkey/menu click.
- No new permissions: Carbon hotkeys and existing Accessibility trust are sufficient.
- No dialogs on failure: `NSSound.beep()` + `Log.shared` lines only.
- Unit tests live only in `Tests/WindowKeeperCoreTests` (Core target). This feature adds no Core logic, so verification is `swift build` + the manual checklist in Task 5. Do not add AX/Carbon code to WindowKeeperCore.
- Spec: `docs/superpowers/specs/2026-07-30-send-it-back-design.md`.
- Version bump to 1.7.0 happens in Task 5 only (CHANGELOG.md + `let version` in `Sources/WindowKeeper/main.swift`).

---

### Task 1: HotkeyService

**Files:**
- Create: `Sources/WindowKeeper/HotkeyService.swift`

**Interfaces:**
- Consumes: nothing from this plan.
- Produces: `final class HotkeyService` with `init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void)` and static constants `HotkeyService.keyO`, `HotkeyService.optionCommand`. Task 4 constructs it.

- [ ] **Step 1: Write the file**

```swift
import AppKit
import Carbon.HIToolbox

/// Registers one global hotkey via Carbon RegisterEventHotKey — the standard
/// mechanism for menu-bar apps: no extra permissions, works while any app is
/// focused, and consumes the keystroke so the focused app never sees it.
final class HotkeyService {
    static let keyO = UInt32(kVK_ANSI_O)
    static let optionCommand = UInt32(optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    /// Fails (returning nil) only if Carbon refuses the registration —
    /// e.g. another app already owns the exact combo.
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData)
                    .takeUnretainedValue()
                service.onPress()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef)
        guard installStatus == noErr else {
            Log.shared.error("Hotkey handler install failed: \(installStatus)")
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x574B4859), // 'WKHY'
                                     id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(),
                                                 0, &hotKeyRef)
        guard registerStatus == noErr else {
            Log.shared.error("Hotkey registration failed: \(registerStatus)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (no warnings from the new file)

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowKeeper/HotkeyService.swift
git commit -m "Add HotkeyService: Carbon global-hotkey wrapper"
```

---

### Task 2: AccessibilityService.focusedWindow(pid:)

**Files:**
- Modify: `Sources/WindowKeeper/AccessibilityService.swift` (add one function inside `enum AccessibilityService`, after `windows(pid:)`)

**Interfaces:**
- Consumes: nothing from this plan.
- Produces: `static func focusedWindow(pid: pid_t) -> AXUIElement?`. Task 3 calls it.

- [ ] **Step 1: Add the function**

Insert after the closing brace of `static func windows(pid:)`:

```swift
    /// The window that currently has focus in the given app, or nil if the
    /// app has none (no windows, or focus is on a non-window element).
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let window = value else { return nil }
        return (window as! AXUIElement)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowKeeper/AccessibilityService.swift
git commit -m "Add AccessibilityService.focusedWindow(pid:)"
```

---

### Task 3: WindowManager.sendFocusedWindowBack()

**Files:**
- Modify: `Sources/WindowKeeper/WindowManager.swift` (add one method in the `// MARK: - Presets` section, after `func setMagicPreset(id:)`)

**Interfaces:**
- Consumes: `AccessibilityService.focusedWindow(pid:)` (Task 2); existing `magicPreset`, `assignedTargets(for:savedFrames:displays:)`, `place(windows:targets:bundleID:)`, `AccessibilityService.windows(pid:)`.
- Produces: `func sendFocusedWindowBack()` (internal, no arguments, no return). Tasks 4 and 5 call it from the hotkey and the menu.

- [ ] **Step 1: Add the method**

```swift
    /// ⌥⌘O — move ONLY the focused window of the frontmost app back to its
    /// place in the magic preset. Runs the same matching as a full restore so
    /// look-alike windows (browser profiles) return to their own spot, but
    /// applies just the one target. Every refusal beeps and logs; no dialogs.
    func sendFocusedWindowBack() {
        guard config.enabled else {
            NSSound.beep()
            Log.shared.info("Send-back ignored: WindowKeeper is disabled")
            return
        }
        guard let preset = magicPreset else {
            NSSound.beep()
            Log.shared.info("Send-back ignored: no magic preset is set")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            NSSound.beep()
            Log.shared.info("Send-back ignored: no frontmost application")
            return
        }
        let appName = app.localizedName ?? bundleID
        guard let saved = preset.frames[bundleID], !saved.isEmpty else {
            NSSound.beep()
            Log.shared.info("Send-back: no saved place for \(appName) "
                + "in preset '\(preset.name)'")
            return
        }
        guard let focused = AccessibilityService.focusedWindow(
            pid: app.processIdentifier) else {
            NSSound.beep()
            Log.shared.info("Send-back: \(appName) has no focused window")
            return
        }
        let windows = AccessibilityService.windows(pid: app.processIdentifier)
        guard let index = windows.firstIndex(where: { CFEqual($0, focused) }) else {
            NSSound.beep()
            Log.shared.info("Send-back: focused window of \(appName) is not a "
                + "standard window")
            return
        }
        let targets = assignedTargets(for: windows, savedFrames: saved,
                                      displays: DisplayInfo.current())
        guard let target = targets[index] else {
            NSSound.beep()
            Log.shared.info("Send-back: no saved frame matched the focused "
                + "\(appName) window (preset saved \(saved.count) window(s))")
            return
        }
        Log.shared.info("Send-back: returning focused \(appName) window to its "
            + "place in '\(preset.name)'")
        place(windows: [focused], targets: [target], bundleID: bundleID)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Run existing tests (must stay green)**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (this task changes no Core logic).

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowKeeper/WindowManager.swift
git commit -m "Add sendFocusedWindowBack: single-window restore from magic preset"
```

---

### Task 4: Wire hotkey + menu item

**Files:**
- Modify: `Sources/WindowKeeper/AppDelegate.swift` (hold + register the hotkey)
- Modify: `Sources/WindowKeeper/StatusMenuController.swift` (menu item under the magic button)

**Interfaces:**
- Consumes: `HotkeyService` (Task 1), `WindowManager.sendFocusedWindowBack()` (Task 3).
- Produces: user-facing trigger; nothing consumed by later tasks.

- [ ] **Step 1: AppDelegate — add property and registration**

Add a property next to the existing ones:

```swift
    private var hotkeyService: HotkeyService?
```

At the end of `applicationDidFinishLaunching`, after `manager.start()`:

```swift
        hotkeyService = HotkeyService(keyCode: HotkeyService.keyO,
                                      modifiers: HotkeyService.optionCommand) {
            [weak self] in self?.manager.sendFocusedWindowBack()
        }
        if hotkeyService == nil {
            Log.shared.error("⌥⌘O hotkey unavailable — Send Back works only "
                + "from the menu")
        }
```

- [ ] **Step 2: StatusMenuController — add the menu item**

In `buildMenu(_:)`, replace the magic-button block

```swift
        if trusted, let preset = manager.magicPreset {
            menu.addItem(makeMagicButton(for: preset))
            menu.addItem(.separator())
        }
```

with

```swift
        if trusted, let preset = manager.magicPreset {
            menu.addItem(makeMagicButton(for: preset))
            menu.addItem(makeSendBackItem(for: preset))
            menu.addItem(.separator())
        }
```

Add after `makeMagicButton(for:)`:

```swift
    /// Single-window restore: sits right under the magic button and shows the
    /// ⌥⌘O shortcut. The frontmost app is whatever the user was just using —
    /// clicking the status item doesn't change it.
    private func makeSendBackItem(for preset: LayoutPreset) -> NSMenuItem {
        let item = NSMenuItem(title: "Send Focused Window Back",
                              action: #selector(sendFocusedWindowBack),
                              keyEquivalent: "o")
        item.keyEquivalentModifierMask = [.option, .command]
        item.target = self
        item.toolTip = "Move only the focused window of the app you're using "
            + "back to its place in “\(preset.name)”. Everything else stays put."
        return item
    }

    @objc private func sendFocusedWindowBack() {
        manager.sendFocusedWindowBack()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowKeeper/AppDelegate.swift Sources/WindowKeeper/StatusMenuController.swift
git commit -m "Wire Send Focused Window Back to global ⌥⌘O and the status menu"
```

---

### Task 5: Version 1.7.0, changelog, install, manual verification

**Files:**
- Modify: `Sources/WindowKeeper/main.swift` (`let version = "1.6.1"` → `"1.7.0"`)
- Modify: `CHANGELOG.md` (new section at top)
- Modify: `README.md` (add feature bullet under Features)

**Interfaces:**
- Consumes: everything above.
- Produces: released build.

- [ ] **Step 1: Bump version**

In `Sources/WindowKeeper/main.swift`: `let version = "1.7.0"`

- [ ] **Step 2: CHANGELOG entry** (insert directly under `# Changelog`)

```markdown
## [1.7.0] — 2026-07-30

### Added
- **Send It Back (⌥⌘O).** Working in an app usually means making its window
  bigger; switching tasks used to mean either dragging it back by hand or
  firing the full Restore. A global ⌥⌘O ("O for original position") now moves
  ONLY the focused window of the frontmost app back to its place in the magic
  preset — the app's other windows and every other app stay exactly where
  they are. The same action lives in the menu right under the Restore button.
  Matching reuses the restore logic, so a browser-profile window returns to
  its own saved spot, not its sibling's. When there's nothing to do — no
  magic preset, the app isn't in it, or no focused window — WindowKeeper
  beeps and writes one honest log line instead of showing a dialog. Plain ⌘O
  was deliberately avoided: it would have hijacked "Open file" in every app.
```

- [ ] **Step 3: README feature bullet** (add to the Features list after "Magic button")

```markdown
- **Send It Back (⌥⌘O)** — enlarged an app to focus on it? One keystroke puts
  just that window back to its preset place; nothing else moves.
```

- [ ] **Step 4: Full build + tests**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: build complete, all tests pass.

- [ ] **Step 5: Install and manually verify**

Run: `make install` then relaunch the app. Checklist:
1. Enlarge a preset app's window → press ⌥⌘O → it returns to its preset frame; other windows untouched.
2. With two Chrome windows moved, focus one → ⌥⌘O → only that one returns.
3. Focus an app not in the preset → beep, log line "no saved place for …".
4. In another app press plain ⌘O → its Open dialog still works.
5. Menu shows "Send Focused Window Back ⌥⌘O" under the Restore button; clicking it acts on the app you were using.

Record outcomes in the commit message or a note; failures loop back to the relevant task.

- [ ] **Step 6: Commit**

```bash
git add Sources/WindowKeeper/main.swift CHANGELOG.md README.md
git commit -m "Send It Back (⌥⌘O) single-window restore (1.7.0)"
```
