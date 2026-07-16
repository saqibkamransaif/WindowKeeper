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
                                 displays: [DisplayInfo],
                                 title: String? = nil) -> SavedFrame {
        let center = CGPoint(x: frame.x + frame.width / 2,
                             y: frame.y + frame.height / 2)
        let owner = displays.first { $0.visibleRect.contains(center) }
            ?? displays.first { $0.isMain }
            ?? displays.first
        guard let owner else {
            return SavedFrame(displayUUID: nil, relX: frame.x, relY: frame.y,
                              width: frame.width, height: frame.height, title: title)
        }
        return SavedFrame(displayUUID: owner.uuid,
                          relX: frame.x - owner.visibleTopLeftAX.x,
                          relY: frame.y - owner.visibleTopLeftAX.y,
                          width: frame.width, height: frame.height, title: title)
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

    /// Assign saved frames to windows by identity and proximity, not list
    /// order. macOS reports windows in z-order, so activating a different
    /// window (e.g. switching browser profiles) reorders the list —
    /// order-based matching then shuffles every window. Assignment rules:
    /// 1. Slots and windows sharing a title key (the trailing " - " token,
    ///    where browsers put the profile name) match each other first.
    /// 2. A window already sitting on a saved frame keeps it.
    /// 3. Remaining windows claim the globally closest free frame — but a
    ///    keyed slot never grabs a window that clearly belongs to a
    ///    different identity (both keyed, keys differ).
    /// 4. Windows whose frame can't be read take leftover frames in order.
    /// Windows beyond the saved count get nil (left where they are).
    public static func assignTargets(current: [WindowFrame?],
                                     saved: [WindowFrame],
                                     currentTitles: [String?] = [],
                                     savedTitles: [String?] = []) -> [WindowFrame?] {
        var result = [WindowFrame?](repeating: nil, count: current.count)
        let windowKeys = current.indices.map { i in
            i < currentTitles.count ? titleKey(currentTitles[i]) : nil
        }
        let slotKeys = saved.indices.map { i in
            i < savedTitles.count ? titleKey(savedTitles[i]) : nil
        }
        var freeWindows = Array(current.indices)
        var freeSlots = Array(saved.indices)

        // Identity pass: each key shared by a slot and a window forms a
        // group; assignment inside the group is by frame proximity.
        var seenKeys = Set<String>()
        for s in freeSlots {
            guard let key = slotKeys[s], seenKeys.insert(key).inserted else { continue }
            let groupSlots = freeSlots.filter { slotKeys[$0] == key }
            let groupWindows = freeWindows.filter { windowKeys[$0] == key }
            guard !groupWindows.isEmpty else { continue }
            matchByFrame(windows: groupWindows, slots: groupSlots,
                         current: current, saved: saved,
                         result: &result, freeWindows: &freeWindows,
                         freeSlots: &freeSlots)
        }

        // General pass: whatever is left, by frame proximity. Known-different
        // identities never cross; unknown (key-less) ones behave as before.
        matchByFrame(windows: freeWindows, slots: freeSlots,
                     current: current, saved: saved,
                     result: &result, freeWindows: &freeWindows,
                     freeSlots: &freeSlots,
                     compatible: { w, s in
                         windowKeys[w] == nil || slotKeys[s] == nil
                             || windowKeys[w] == slotKeys[s]
                     })
        return result
    }

    /// Frame-based matching over index subsets: exact occupants keep their
    /// slot, then closest pairs, then unreadable windows take leftovers.
    private static func matchByFrame(windows: [Int], slots: [Int],
                                     current: [WindowFrame?], saved: [WindowFrame],
                                     result: inout [WindowFrame?],
                                     freeWindows: inout [Int], freeSlots: inout [Int],
                                     compatible: (Int, Int) -> Bool = { _, _ in true }) {
        var poolWindows = windows
        var poolSlots = slots

        func claim(_ w: Int, _ s: Int) {
            result[w] = saved[s]
            poolWindows.removeAll { $0 == w }
            poolSlots.removeAll { $0 == s }
            freeWindows.removeAll { $0 == w }
            freeSlots.removeAll { $0 == s }
        }

        // Exact occupants first, so a nearby moved window can't steal a slot.
        for w in poolWindows {
            guard let frame = current[w],
                  let s = poolSlots.first(where: {
                      compatible(w, $0) && framesMatch(saved[$0], frame)
                  }) else { continue }
            claim(w, s)
        }

        // Globally closest remaining pairs.
        while !poolSlots.isEmpty {
            var best: (w: Int, s: Int, score: Double)?
            for w in poolWindows {
                guard let frame = current[w] else { continue }
                for s in poolSlots where compatible(w, s) {
                    let score = placementDistance(frame, saved[s])
                    if best == nil || score < best!.score { best = (w, s, score) }
                }
            }
            guard let match = best else { break }
            claim(match.w, match.s)
        }

        // Unreadable windows soak up leftover slots.
        for w in poolWindows where result[w] == nil {
            guard let s = poolSlots.first(where: { compatible(w, $0) }) else { continue }
            claim(w, s)
        }
    }

    /// Identity key of a window title: the last " - "-separated token, where
    /// browsers append the profile name (e.g. "Tab - Comet - Saqib Kamran" →
    /// "Saqib Kamran"). Titles without that structure have no key.
    private static func titleKey(_ title: String?) -> String? {
        guard let title else { return nil }
        let parts = title.components(separatedBy: " - ")
        guard parts.count >= 2, let last = parts.last else { return nil }
        let key = last.trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// How far apart two frames are for assignment purposes: center distance
    /// plus a size-difference penalty, so a same-sized window wins over a
    /// differently-sized one at equal distance.
    private static func placementDistance(_ a: WindowFrame, _ b: WindowFrame) -> Double {
        let dx = (a.x + a.width / 2) - (b.x + b.width / 2)
        let dy = (a.y + a.height / 2) - (b.y + b.height / 2)
        return (dx * dx + dy * dy).squareRoot()
            + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
