import AppKit
import WindowKeeperCore

/// Builds the status-bar menu. It holds only the everyday actions; presets,
/// managed apps and settings live in the Preferences window. The menu is
/// rebuilt each time it opens so names and shortcuts stay current.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager: WindowManager
    private lazy var preferences = PreferencesWindowController(manager: manager)

    init(manager: WindowManager) {
        self.manager = manager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "uiwindow.split.2x1",
                                   accessibilityDescription: "WindowKeeper")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        let trusted = AccessibilityService.isTrusted()
        if !trusted {
            menu.addItem(item("⚠️ Grant Accessibility Access…", #selector(requestAccess)))
            menu.addItem(.separator())
        }

        if trusted {
            let preset = manager.magicPreset
            if let preset { menu.addItem(makeRestoreButton(for: preset)) }
            let name = preset?.name ?? PresetCatalog.defaultName
            let remember = item("Remember Current Layout", #selector(rememberCurrentLayout))
            remember.toolTip = "Save every open window's place as “\(name)”. "
                + "Apps with no open windows leave the layout."
            menu.addItem(remember)
            if let preset { menu.addItem(makeSendBackItem(for: preset)) }
            menu.addItem(.separator())
        }

        menu.addItem(item("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WindowKeeper",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    /// The one-click restore: big, bold, accent-tinted, at the very top.
    private func makeRestoreButton(for preset: LayoutPreset) -> NSMenuItem {
        let title = "Restore \(preset.name)"
        let menuItem = item(title, #selector(restoreDefault), key: "r")
        menuItem.attributedTitle = NSAttributedString(
            string: title, attributes: [.font: NSFont.systemFont(ofSize: 14.5, weight: .semibold)])
        let symbol = NSImage(systemSymbolName: "wand.and.stars",
                             accessibilityDescription: "Restore layout")
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            .applying(.init(paletteColors: [.controlAccentColor]))
        menuItem.image = symbol?.withSymbolConfiguration(config)
        menuItem.toolTip = "Launch every app in “\(preset.name)” and put every window "
            + "back in its saved place, on all displays."
        return menuItem
    }

    /// Shows the global ⌥⌘R shortcut. The frontmost app is whatever the user
    /// was just using: clicking the status item doesn't change it.
    private func makeSendBackItem(for preset: LayoutPreset) -> NSMenuItem {
        let menuItem = item("Send Focused Window Back", #selector(sendFocusedWindowBack), key: "r")
        menuItem.keyEquivalentModifierMask = [.option, .command]
        menuItem.toolTip = "Move only the focused window of the app you're using "
            + "back to its place in “\(preset.name)”. Everything else stays put."
        return menuItem
    }

    // MARK: - Actions

    @objc private func requestAccess() {
        _ = AccessibilityService.isTrusted(prompt: true)
    }

    @objc private func restoreDefault() {
        guard let preset = manager.magicPreset else { return }
        manager.applyPreset(id: preset.id)
    }

    @objc private func sendFocusedWindowBack() {
        manager.sendFocusedWindowBack()
    }

    @objc private func rememberCurrentLayout() {
        let name = manager.magicPreset?.name ?? PresetCatalog.defaultName
        guard Dialogs.confirm(title: "Remember current layout as “\(name)”?",
                              message: "Every open window's place is saved. Apps with no "
                                + "open windows leave “\(name)”.",
                              button: "Remember") else { return }
        let result = manager.rememberCurrentLayoutAsDefault()
        Dialogs.captureSummary(captured: result.captured, removed: result.removed,
                               presetName: result.presetName)
        preferences.refresh()
    }

    @objc private func openPreferences() {
        preferences.show()
    }
}
