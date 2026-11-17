import AppKit

/// Small modal dialogs shared by the menu and the Preferences window.
enum Dialogs {
    /// Ask for a name. Returns nil on Cancel.
    static func askName(title: String, message: String, button: String,
                        initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name"
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Yes or no question. `destructive` marks the confirm button red.
    static func confirm(title: String, message: String, button: String,
                        destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        if destructive { alert.buttons.first?.hasDestructiveAction = true }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Say exactly what a layout now holds: the apps captured on screen and,
    /// for a re-save, the apps dropped because they had no open windows.
    static func captureSummary(captured: [String], removed: [String], presetName: String) {
        let alert = NSAlert()
        if captured.isEmpty {
            alert.alertStyle = .warning
            alert.messageText = "Nothing was captured"
            alert.informativeText = "No apps have open windows right now, so “\(presetName)” "
                + "was not changed. Open and arrange the apps you want, then try again."
        } else {
            alert.messageText = "“\(presetName)” remembered"
            var text = "Captured: \(captured.joined(separator: ", "))"
            if !removed.isEmpty {
                text += "\n\nRemoved (no open windows): \(removed.joined(separator: ", "))"
            }
            alert.informativeText = text
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
