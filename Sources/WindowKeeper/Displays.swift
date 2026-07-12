import AppKit
import WindowKeeperCore

extension DisplayInfo {
    /// Snapshot of currently attached displays in AX coordinates, keyed by
    /// hardware UUID so saved frames can find their display again after
    /// arrangement changes.
    static func current() -> [DisplayInfo] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.enumerated().compactMap { index, screen in
            guard let uuid = screen.displayUUID else { return nil }
            let visible = screen.visibleFrame
            let topLeftAX = CGPoint(x: visible.minX,
                                    y: primaryHeight - visible.maxY)
            return DisplayInfo(uuid: uuid,
                               isMain: index == 0,
                               visibleTopLeftAX: topLeftAX,
                               visibleSize: visible.size)
        }
    }
}

extension NSScreen {
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else {
            return nil
        }
        let uuid = uuidRef.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}
