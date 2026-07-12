import Foundation

/// JSON persistence for config, remembered frames, and presets.
/// The directory is injectable so tests can point at a temp location.
public final class LayoutStore {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var framesURL: URL { directory.appendingPathComponent("frames.json") }
    public var presetsURL: URL { directory.appendingPathComponent("presets.json") }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowKeeper", isDirectory: true)
    }

    public init(directory: URL = LayoutStore.defaultDirectory()) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // MARK: - Config

    public func loadConfig() -> Config {
        load(Config.self, from: configURL) ?? Config()
    }

    public func save(config: Config) throws {
        try write(config, to: configURL)
    }

    // MARK: - Remembered frames

    public func loadFrames() -> [String: [WindowFrame]] {
        load([String: [WindowFrame]].self, from: framesURL) ?? [:]
    }

    public func save(frames: [String: [WindowFrame]]) throws {
        try write(frames, to: framesURL)
    }

    // MARK: - Presets

    public func loadPresets() -> [LayoutPreset] {
        load([LayoutPreset].self, from: presetsURL) ?? []
    }

    public func save(presets: [LayoutPreset]) throws {
        try write(presets, to: presetsURL)
    }

    // MARK: - Internals

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
