import Foundation
import CoreGraphics

/// A window frame in Accessibility coordinates (origin at top-left of the
/// primary display, y grows downward). All persisted frames use this space.
public struct WindowFrame: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y,
                  width: rect.size.width, height: rect.size.height)
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// How a managed app's windows are placed.
public enum PlacementMode: Codable, Equatable {
    /// Re-apply the last frames the user arranged.
    case remember
    /// Snap every window to a named zone.
    case zone(String)

    private enum CodingKeys: String, CodingKey { case kind, zoneID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "zone":
            self = .zone(try c.decode(String.self, forKey: .zoneID))
        default:
            self = .remember
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remember:
            try c.encode("remember", forKey: .kind)
        case .zone(let id):
            try c.encode("zone", forKey: .kind)
            try c.encode(id, forKey: .zoneID)
        }
    }
}

/// A rule for one application, keyed by bundle identifier.
public struct AppRule: Codable, Equatable {
    public var bundleID: String
    public var displayName: String
    public var mode: PlacementMode
    public var enabled: Bool

    public init(bundleID: String, displayName: String,
                mode: PlacementMode = .remember, enabled: Bool = true) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.mode = mode
        self.enabled = enabled
    }
}

/// A screen region expressed as fractions (0...1) of a display's visible frame,
/// measured from the top-left. Fractional zones adapt to any monitor size.
public struct Zone: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var fx: Double
    public var fy: Double
    public var fw: Double
    public var fh: Double
    /// Index into NSScreen.screens; 0 is the main display.
    public var displayIndex: Int

    public init(id: String, name: String,
                fx: Double, fy: Double, fw: Double, fh: Double,
                displayIndex: Int = 0) {
        self.id = id
        self.name = name
        self.fx = fx
        self.fy = fy
        self.fw = fw
        self.fh = fh
        self.displayIndex = displayIndex
    }
}

/// A named snapshot of window frames across managed apps.
public struct LayoutPreset: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var frames: [String: [WindowFrame]]

    public init(id: String = UUID().uuidString, name: String,
                frames: [String: [WindowFrame]]) {
        self.id = id
        self.name = name
        self.frames = frames
    }
}

/// Root configuration document persisted to config.json.
public struct Config: Codable, Equatable {
    public var enabled: Bool
    public var rules: [AppRule]
    public var zones: [Zone]

    public init(enabled: Bool = true, rules: [AppRule] = [],
                zones: [Zone] = Zone.builtIn) {
        self.enabled = enabled
        self.rules = rules
        self.zones = zones
    }

    private enum CodingKeys: String, CodingKey { case enabled, rules, zones }

    /// Tolerant decoding: a hand-edited config missing a key (or with an empty
    /// zones list) falls back to defaults instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        rules = try c.decodeIfPresent([AppRule].self, forKey: .rules) ?? []
        let decodedZones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? []
        zones = decodedZones.isEmpty ? Zone.builtIn : decodedZones
    }

    public func rule(for bundleID: String) -> AppRule? {
        rules.first { $0.bundleID == bundleID && $0.enabled }
    }

    public func zone(id: String) -> Zone? {
        zones.first { $0.id == id }
    }

    public mutating func upsert(rule: AppRule) {
        if let i = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            rules[i] = rule
        } else {
            rules.append(rule)
        }
    }

    public mutating func removeRule(bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
    }
}

extension Zone {
    /// Built-in zones. Halves, thirds and two-thirds cover the layouts that make
    /// an ultra-wide screen useful; center is a comfortable reading position.
    public static let builtIn: [Zone] = [
        Zone(id: "left-half", name: "Left Half", fx: 0, fy: 0, fw: 0.5, fh: 1),
        Zone(id: "right-half", name: "Right Half", fx: 0.5, fy: 0, fw: 0.5, fh: 1),
        Zone(id: "left-third", name: "Left Third", fx: 0, fy: 0, fw: 1.0 / 3, fh: 1),
        Zone(id: "middle-third", name: "Middle Third", fx: 1.0 / 3, fy: 0, fw: 1.0 / 3, fh: 1),
        Zone(id: "right-third", name: "Right Third", fx: 2.0 / 3, fy: 0, fw: 1.0 / 3, fh: 1),
        Zone(id: "left-two-thirds", name: "Left Two Thirds", fx: 0, fy: 0, fw: 2.0 / 3, fh: 1),
        Zone(id: "right-two-thirds", name: "Right Two Thirds", fx: 1.0 / 3, fy: 0, fw: 2.0 / 3, fh: 1),
        Zone(id: "center", name: "Center", fx: 0.2, fy: 0.05, fw: 0.6, fh: 0.9),
        Zone(id: "maximize", name: "Maximize", fx: 0, fy: 0, fw: 1, fh: 1),
    ]
}
