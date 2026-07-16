import AppKit
import ApplicationServices
import WindowKeeperCore

/// Thin wrappers around the Accessibility (AX) API: enumerate app windows
/// and read/write frames.
enum AccessibilityService {

    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Standard (non-minimized is included; sheets/popovers are not) windows of a pid.
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let list = value as? [AXUIElement] else {
            Log.shared.error("AX windows query failed for pid \(pid): "
                + "error \(result.rawValue), value \(value == nil ? "nil" : "non-nil")")
            return []
        }
        return list.filter { element in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == kAXWindowRole as String else { return false }
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            // Only standard document/app windows; skip panels, dialogs handled by apps.
            return (subrole as? String) == kAXStandardWindowSubrole as String
                || subrole == nil
        }
    }

    static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success
        else { return nil }
        let title = value as? String
        return title?.isEmpty == true ? nil : title
    }

    static func frame(of window: AXUIElement) -> WindowFrame? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return WindowFrame(rect: CGRect(origin: point, size: size))
    }

    enum PlacementResult {
        case placed          // window ended up at the target frame
        case adjusted(WindowFrame) // macOS clamped it; final frame attached
        case failed
    }

    /// Apply a frame and verify what macOS actually did. AX set calls return
    /// success even when the WindowServer clamps or relocates the window
    /// (common on cross-display moves), so trust only the readback. Position
    /// is set before size: moving first gets the window onto the target
    /// display so the size isn't clamped against the source display.
    @discardableResult
    static func setFrame(_ frame: WindowFrame, on window: AXUIElement,
                         attempts: Int = 3) -> PlacementResult {
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return .failed }

        var lastSeen: WindowFrame?
        for attempt in 0..<max(1, attempts) {
            let r1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            let r2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let r3 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            guard r1 == .success, r2 == .success, r3 == .success else { return .failed }
            guard let current = self.frame(of: window) else { return .failed }
            if LayoutEngine.framesMatch(current, frame) { return .placed }
            // If two consecutive attempts land on the same wrong frame, macOS
            // is enforcing it — stop fighting and report the adjustment.
            if let last = lastSeen, LayoutEngine.framesMatch(current, last) {
                return .adjusted(current)
            }
            lastSeen = current
            if attempt < attempts - 1 { usleep(120_000) }
        }
        return .adjusted(lastSeen ?? frame)
    }

    // MARK: - New-window creation

    /// Ask an app to open one more window by pressing its own "New Window"
    /// menu item (File → New Window, Shell → New Window with Profile…,
    /// File → New Finder Window, …). Works without activating the app and
    /// without synthetic keystrokes, so it can never land in the wrong app or
    /// trigger an unrelated ⌘N action. Returns false when no such item exists.
    static func openNewWindow(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString,
                                            &value) == .success,
              let menuBar = value else { return false }
        guard let item = findNewWindowItem(in: menuBar as! AXUIElement, depth: 0)
        else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Depth-first search of the menu tree for an enabled item that opens a
    /// window: exact "New Window", a variant like "New Window with Profile –
    /// Basic", or the New…Window shape ("New Finder Window"). Excludes
    /// look-alikes such as "New File"/"New Tab" by requiring both words.
    private static func findNewWindowItem(in element: AXUIElement,
                                          depth: Int) -> AXUIElement? {
        guard depth < 5 else { return nil }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        var fallback: AXUIElement?
        for child in children {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            if let title = titleValue as? String, isEnabled(child) {
                if title == "New Window" || title.hasPrefix("New Window ") {
                    if !hasSubmenu(child) { return child }
                } else if fallback == nil, title.hasPrefix("New "),
                          title.hasSuffix(" Window") || title.hasSuffix(" Window…") {
                    if !hasSubmenu(child) { fallback = child }
                }
            }
            if let found = findNewWindowItem(in: child, depth: depth + 1) {
                return found
            }
        }
        return fallback
    }

    private static func hasSubmenu(_ item: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString,
                                            &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        return !children.isEmpty
    }

    private static func isEnabled(_ item: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString,
                                            &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

}
