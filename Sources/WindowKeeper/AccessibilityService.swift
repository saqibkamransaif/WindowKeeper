import AppKit
import ApplicationServices
import WindowKeeperCore

/// Thin wrappers around the Accessibility (AX) API: enumerate app windows,
/// read/write frames, and observe window events.
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
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
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

    /// Apply a frame. Position and size are set separately in AX; setting
    /// size → position → size again works around apps that clamp one axis
    /// until the other changes (a long-standing AX quirk).
    @discardableResult
    static func setFrame(_ frame: WindowFrame, on window: AXUIElement) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let r1 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let r2 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        let r3 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return r1 == .success && r2 == .success && r3 == .success
    }

    /// Create an observer on an app for window lifecycle/geometry events.
    /// `refcon` is passed through to the C callback.
    static func makeObserver(pid: pid_t,
                             callback: @escaping AXObserverCallback,
                             refcon: UnsafeMutableRawPointer?) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else { return nil }
        let app = AXUIElementCreateApplication(pid)
        for notification in [kAXWindowCreatedNotification,
                             kAXWindowMovedNotification,
                             kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, app, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .defaultMode)
        return observer
    }

    static func removeObserver(_ observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                              AXObserverGetRunLoopSource(observer),
                              .defaultMode)
    }
}
