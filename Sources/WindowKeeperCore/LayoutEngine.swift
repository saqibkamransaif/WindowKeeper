import Foundation
import CoreGraphics

/// Pure layout math. No AppKit or Accessibility dependencies so it can be
/// tested headlessly.
public enum LayoutEngine {

    /// Convert a Cocoa rect (bottom-left origin, y up — NSScreen space) to an
    /// AX frame (top-left origin, y down). `primaryHeight` is the full height
    /// of the primary display, which anchors both coordinate systems.
    public static func axFrame(fromCocoa rect: CGRect, primaryHeight: CGFloat) -> WindowFrame {
        WindowFrame(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Inverse of `axFrame(fromCocoa:primaryHeight:)`.
    public static func cocoaRect(fromAX frame: WindowFrame, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.x,
            y: Double(primaryHeight) - frame.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// Resolve a fractional zone against a display's visible frame (Cocoa
    /// space) into an absolute AX frame ready to apply to a window.
    public static func resolve(zone: Zone, visibleFrame: CGRect,
                               primaryHeight: CGFloat) -> WindowFrame {
        // Work in AX space: convert the visible frame's top-left first.
        let topLeftY: Double = Double(primaryHeight) - Double(visibleFrame.maxY)
        let x: Double = Double(visibleFrame.origin.x) + zone.fx * Double(visibleFrame.width)
        let y: Double = topLeftY + zone.fy * Double(visibleFrame.height)
        let w: Double = zone.fw * Double(visibleFrame.width)
        let h: Double = zone.fh * Double(visibleFrame.height)
        return WindowFrame(x: halfPoint(x), y: halfPoint(y),
                           width: halfPoint(w), height: halfPoint(h))
    }

    // MARK: - Saved frame ↔ absolute frame

    /// Convert a live window frame into a display-relative SavedFrame. The
    /// owning display is the one containing the window's center (falling back
    /// to the main display), so the frame survives arrangement changes.
    public static func makeSaved(from frame: WindowFrame,
                                 displays: [DisplayInfo]) -> SavedFrame {
        let center = CGPoint(x: frame.x + frame.width / 2,
                             y: frame.y + frame.height / 2)
        let owner = displays.first { $0.visibleRect.contains(center) }
            ?? displays.first { $0.isMain }
            ?? displays.first
        guard let owner else {
            return SavedFrame(displayUUID: nil, relX: frame.x, relY: frame.y,
                              width: frame.width, height: frame.height)
        }
        return SavedFrame(displayUUID: owner.uuid,
                          relX: frame.x - owner.visibleTopLeftAX.x,
                          relY: frame.y - owner.visibleTopLeftAX.y,
                          width: frame.width, height: frame.height)
    }

    /// Resolve a SavedFrame against the current displays into an absolute AX
    /// frame that is guaranteed to be visible:
    /// - display-relative + display present → exact position on that display
    /// - display-relative + display missing → same offset on the main display
    /// - legacy absolute → used as-is if still on some display, else clamped
    ///   into the main display
    /// The result is always clamped inside its target display's visible area.
    public static func resolve(saved: SavedFrame,
                               displays: [DisplayInfo]) -> WindowFrame? {
        guard !displays.isEmpty else { return nil }
        let main = displays.first { $0.isMain } ?? displays[0]

        if let uuid = saved.displayUUID {
            let target = displays.first { $0.uuid == uuid } ?? main
            let frame = WindowFrame(x: target.visibleTopLeftAX.x + saved.relX,
                                    y: target.visibleTopLeftAX.y + saved.relY,
                                    width: saved.width, height: saved.height)
            return clamp(frame, into: target)
        }

        // Legacy absolute frame: keep it if its center is still on a display.
        let absolute = WindowFrame(x: saved.relX, y: saved.relY,
                                   width: saved.width, height: saved.height)
        let center = CGPoint(x: absolute.x + absolute.width / 2,
                             y: absolute.y + absolute.height / 2)
        if let owner = displays.first(where: { $0.visibleRect.contains(center) }) {
            return clamp(absolute, into: owner)
        }
        return clamp(absolute, into: main)
    }

    /// Fit a frame inside a display's visible area: shrink if oversized, then
    /// shift so it lies fully inside. Prevents macOS from silently relocating
    /// windows it considers off-screen.
    public static func clamp(_ frame: WindowFrame,
                             into display: DisplayInfo) -> WindowFrame {
        let visible = display.visibleRect
        let width = min(frame.width, Double(visible.width))
        let height = min(frame.height, Double(visible.height))
        var x = frame.x
        var y = frame.y
        x = max(Double(visible.minX), min(x, Double(visible.maxX) - width))
        y = max(Double(visible.minY), min(y, Double(visible.maxY) - height))
        return WindowFrame(x: x, y: y, width: width, height: height)
    }

    /// Round to the nearest half point so frames land on pixel boundaries on
    /// both standard and Retina (2x) displays.
    private static func halfPoint(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    /// Whether two frames are effectively the same placement. Apps often
    /// report frames a pixel or two off after an AX set, so compare with a
    /// tolerance to avoid churn.
    public static func framesMatch(_ a: WindowFrame, _ b: WindowFrame,
                                   tolerance: Double = 2.0) -> Bool {
        abs(a.x - b.x) <= tolerance
            && abs(a.y - b.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// Merge a fresh capture into a preset's existing frames. Captured apps
    /// overwrite their entries; apps in `running` that the capture missed
    /// (window in another Space, minimized, or hidden) keep their existing
    /// frames instead of being silently dropped; apps neither captured nor
    /// running are removed. `kept` lists the preserved bundle IDs so callers
    /// can report them.
    public static func mergePresetFrames(
        existing: [String: [SavedFrame]],
        captured: [String: [SavedFrame]],
        running: Set<String>
    ) -> (frames: [String: [SavedFrame]], kept: [String]) {
        var merged = captured
        var kept: [String] = []
        for (bundleID, frames) in existing
        where captured[bundleID] == nil && running.contains(bundleID) {
            merged[bundleID] = frames
            kept.append(bundleID)
        }
        return (merged, kept.sorted())
    }

    /// Target frames for an app's windows given its rule.
    /// - remember: saved frames, applied by window order (nil when none saved).
    /// - zone: the zone frame repeated for every window.
    public static func targetFrames(rule: AppRule,
                                    windowCount: Int,
                                    remembered: [WindowFrame]?,
                                    zoneResolver: (String) -> WindowFrame?) -> [WindowFrame?] {
        guard windowCount > 0 else { return [] }
        switch rule.mode {
        case .remember:
            guard let saved = remembered, !saved.isEmpty else {
                return Array(repeating: nil, count: windowCount)
            }
            return (0..<windowCount).map { i in i < saved.count ? saved[i] : saved.last }
        case .zone(let id):
            let frame = zoneResolver(id)
            return Array(repeating: frame, count: windowCount)
        }
    }
}
