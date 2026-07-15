import AppKit
import WindowKeeperCore

/// Builds and manages the status-bar menu. The menu is rebuilt each time it
/// opens so it always reflects current rules, presets, and running apps.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager: WindowManager

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
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility Access…",
                                  action: #selector(requestAccess), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        if trusted, let preset = manager.magicPreset {
            menu.addItem(makeMagicButton(for: preset))
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(title: "Enabled",
                                 action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = manager.config.enabled ? .on : .off
        menu.addItem(enabled)

        let capture = NSMenuItem(title: "Capture Current Layout",
                                 action: #selector(captureLayout), keyEquivalent: "c")
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())
        menu.addItem(buildPresetsItem())
        menu.addItem(buildManageAppsItem())
        menu.addItem(.separator())

        let openFolder = NSMenuItem(title: "Open Config Folder",
                                    action: #selector(openConfigFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WindowKeeper",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// The one-click restore button: big, bold, accent-tinted, always at the
    /// very top of the menu.
    private func makeMagicButton(for preset: LayoutPreset) -> NSMenuItem {
        let item = NSMenuItem(title: "Restore \(preset.name)",
                              action: #selector(applyMagicPreset), keyEquivalent: "r")
        item.target = self
        item.attributedTitle = NSAttributedString(
            string: "Restore \(preset.name)",
            attributes: [.font: NSFont.systemFont(ofSize: 14.5, weight: .semibold)])
        let symbol = NSImage(systemSymbolName: "wand.and.stars",
                             accessibilityDescription: "Restore layout")
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            .applying(.init(paletteColors: [.controlAccentColor]))
        item.image = symbol?.withSymbolConfiguration(config)
        item.toolTip = "Launch every app in “\(preset.name)” and put every window "
            + "back in its saved place, on all displays."
        return item
    }

    // MARK: - Presets submenu

    private func buildPresetsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let saveNew = NSMenuItem(title: "Save Current as New Preset…",
                                 action: #selector(saveNewPreset), keyEquivalent: "s")
        saveNew.target = self
        submenu.addItem(saveNew)

        if !manager.presets.isEmpty {
            submenu.addItem(.separator())
            for preset in manager.presets {
                let presetItem = NSMenuItem(title: preset.name, action: nil, keyEquivalent: "")
                let actions = NSMenu()

                let apply = NSMenuItem(title: "Apply", action: #selector(applyPreset(_:)), keyEquivalent: "")
                apply.target = self
                apply.representedObject = preset.id
                actions.addItem(apply)

                let update = NSMenuItem(title: "Update from Current Layout",
                                        action: #selector(updatePreset(_:)), keyEquivalent: "")
                update.target = self
                update.representedObject = preset.id
                actions.addItem(update)

                let magic = NSMenuItem(title: "Use as Magic Button",
                                       action: #selector(setMagicPreset(_:)), keyEquivalent: "")
                magic.target = self
                magic.representedObject = preset.id
                magic.state = manager.magicPreset?.id == preset.id ? .on : .off
                actions.addItem(magic)

                actions.addItem(.separator())
                let delete = NSMenuItem(title: "Delete", action: #selector(deletePreset(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = preset.id
                actions.addItem(delete)

                presetItem.submenu = actions
                submenu.addItem(presetItem)
            }
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Manage Apps submenu

    private func buildManageAppsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Manage Apps", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let rule = manager.config.rule(for: bundleID)
            let appItem = NSMenuItem(title: app.localizedName ?? bundleID,
                                     action: nil, keyEquivalent: "")

            let actions = NSMenu()
            let managed = NSMenuItem(title: "Managed",
                                     action: #selector(toggleManaged(_:)), keyEquivalent: "")
            managed.target = self
            managed.representedObject = app
            managed.state = rule != nil ? .on : .off
            actions.addItem(managed)

            if let rule {
                appItem.state = .on
                actions.addItem(.separator())

                let remember = NSMenuItem(title: "Remember Last Position",
                                          action: #selector(setRememberMode(_:)), keyEquivalent: "")
                remember.target = self
                remember.representedObject = bundleID
                if case .remember = rule.mode { remember.state = .on }
                actions.addItem(remember)

                actions.addItem(.separator())
                actions.addItem(sectionLabel("Snap to Zone"))
                for zone in manager.config.zones {
                    let zoneItem = NSMenuItem(title: zone.name,
                                              action: #selector(setZoneMode(_:)), keyEquivalent: "")
                    zoneItem.target = self
                    zoneItem.representedObject = ["bundleID": bundleID, "zoneID": zone.id]
                    if case .zone(let id) = rule.mode, id == zone.id { zoneItem.state = .on }
                    actions.addItem(zoneItem)
                }
            }
            appItem.submenu = actions
            submenu.addItem(appItem)
        }
        item.submenu = submenu
        return item
    }

    private func sectionLabel(_ title: String) -> NSMenuItem {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        label.isEnabled = false
        return label
    }

    // MARK: - Actions

    @objc private func requestAccess() {
        _ = AccessibilityService.isTrusted(prompt: true)
    }

    @objc private func toggleEnabled() {
        manager.setEnabled(!manager.config.enabled)
    }

    @objc private func captureLayout() {
        manager.captureAllFrames()
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(manager.store.directory)
    }

    @objc private func toggleManaged(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        manager.setManaged(sender.state == .off, app: app)
    }

    @objc private func setRememberMode(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        manager.setMode(.remember, bundleID: bundleID)
    }

    @objc private func setZoneMode(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let bundleID = info["bundleID"], let zoneID = info["zoneID"] else { return }
        manager.setMode(.zone(zoneID), bundleID: bundleID)
    }

    @objc private func saveNewPreset() {
        let alert = NSAlert()
        alert.messageText = "Save Layout Preset"
        alert.informativeText = "Captures the current window layout of every open app, across all displays."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let captured = manager.savePreset(named: name.isEmpty ? "Untitled Preset" : name)
            showCaptureSummary(captured: captured, presetName: name)
        }
    }

    /// Tell the user exactly what a preset capture contains — a preset saved
    /// while apps are closed silently misses them, which reads as "apply does
    /// nothing" later.
    private func showCaptureSummary(captured: [String], presetName: String) {
        let alert = NSAlert()
        if captured.isEmpty {
            alert.alertStyle = .warning
            alert.messageText = "Nothing was captured"
            alert.informativeText = "No apps have open windows right now. "
                + "Open the apps you want in the layout, arrange them, then save the preset again."
        } else {
            alert.messageText = "Preset “\(presetName)” saved"
            var text = "Captured: \(captured.joined(separator: ", "))"
            let missing = manager.managedAppsNotRunning()
            if !missing.isEmpty {
                text += "\n\nNot captured (not running): \(missing.joined(separator: ", "))"
            }
            alert.informativeText = text
        }
        alert.runModal()
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        manager.applyPreset(id: id)
    }

    @objc private func applyMagicPreset() {
        guard let preset = manager.magicPreset else { return }
        manager.applyPreset(id: preset.id)
    }

    @objc private func setMagicPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        manager.setMagicPreset(id: id)
    }

    @objc private func updatePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let captured = manager.updatePreset(id: id)
        let name = manager.presets.first { $0.id == id }?.name ?? ""
        showCaptureSummary(captured: captured, presetName: name)
    }

    @objc private func deletePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        manager.deletePreset(id: id)
    }
}
