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

}
