import Foundation

/// Pure helpers for the preset list: which preset is the default (the one
/// the Restore button and the send-back shortcut use) and safe renaming.
public enum PresetCatalog {
    public static let defaultName = "My Setup"

    /// The chosen default, else the most recently saved preset.
    public static func defaultPreset(in presets: [LayoutPreset],
                                     defaultID: String?) -> LayoutPreset? {
        if let defaultID, let chosen = presets.first(where: { $0.id == defaultID }) {
            return chosen
        }
        return presets.last
    }

    /// A new list with one preset renamed, or nil when the name is blank or
    /// the id is unknown. The input list is never changed.
    public static func renaming(_ presets: [LayoutPreset], id: String,
                                to rawName: String) -> [LayoutPreset]? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, presets.contains(where: { $0.id == id }) else { return nil }
        return presets.map { preset in
            guard preset.id == id else { return preset }
            return LayoutPreset(id: preset.id, name: name, frames: preset.frames)
        }
    }

    public static func cleanName(_ rawName: String, fallback: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }
}
