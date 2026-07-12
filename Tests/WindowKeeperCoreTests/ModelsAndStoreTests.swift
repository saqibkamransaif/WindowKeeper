import XCTest
@testable import WindowKeeperCore

final class ModelsAndStoreTests: XCTestCase {

    var tempDir: URL!
    var store: LayoutStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowKeeperTests-\(UUID().uuidString)")
        store = try LayoutStore(directory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Codable round-trips

    func testPlacementModeCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let remember = PlacementMode.remember
        let decodedRemember = try decoder.decode(PlacementMode.self,
                                                 from: encoder.encode(remember))
        XCTAssertEqual(decodedRemember, remember)

        let zone = PlacementMode.zone("left-third")
        let decodedZone = try decoder.decode(PlacementMode.self,
                                             from: encoder.encode(zone))
        XCTAssertEqual(decodedZone, zone)
    }

    func testConfigCodableRoundTrip() throws {
        var config = Config()
        config.upsert(rule: AppRule(bundleID: "com.apple.Safari",
                                    displayName: "Safari", mode: .zone("right-half")))
        config.upsert(rule: AppRule(bundleID: "com.tinyspeck.slackmacgap",
                                    displayName: "Slack"))
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    // MARK: - Config rule management

    func testUpsertReplacesExistingRule() {
        var config = Config()
        config.upsert(rule: AppRule(bundleID: "com.test", displayName: "Test"))
        config.upsert(rule: AppRule(bundleID: "com.test", displayName: "Test",
                                    mode: .zone("center")))
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.rule(for: "com.test")?.mode, .zone("center"))
    }

    func testDisabledRuleIsNotReturned() {
        var config = Config()
        config.upsert(rule: AppRule(bundleID: "com.test", displayName: "Test",
                                    enabled: false))
        XCTAssertNil(config.rule(for: "com.test"))
    }

    func testRemoveRule() {
        var config = Config()
        config.upsert(rule: AppRule(bundleID: "com.test", displayName: "Test"))
        config.removeRule(bundleID: "com.test")
        XCTAssertTrue(config.rules.isEmpty)
    }

    // MARK: - Built-in zones

    func testBuiltInZoneIDsAreUnique() {
        let ids = Zone.builtIn.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testBuiltInZoneFractionsAreWithinBounds() {
        for zone in Zone.builtIn {
            XCTAssertGreaterThanOrEqual(zone.fx, 0)
            XCTAssertGreaterThanOrEqual(zone.fy, 0)
            XCTAssertLessThanOrEqual(zone.fx + zone.fw, 1.0001, "zone \(zone.id)")
            XCTAssertLessThanOrEqual(zone.fy + zone.fh, 1.0001, "zone \(zone.id)")
        }
    }

    // MARK: - Store persistence

    func testConfigPersistsAcrossStoreInstances() throws {
        var config = store.loadConfig()
        config.enabled = false
        config.upsert(rule: AppRule(bundleID: "com.apple.dt.Xcode",
                                    displayName: "Xcode", mode: .zone("left-two-thirds")))
        try store.save(config: config)

        let reloaded = try LayoutStore(directory: tempDir).loadConfig()
        XCTAssertEqual(reloaded, config)
    }

    func testFramesPersistAcrossStoreInstances() throws {
        let frames = ["com.apple.Safari": [
            WindowFrame(x: 2560, y: 25, width: 2560, height: 1415),
            WindowFrame(x: 0, y: 25, width: 1280, height: 700),
        ]]
        try store.save(frames: frames)
        let reloaded = try LayoutStore(directory: tempDir).loadFrames()
        XCTAssertEqual(reloaded, frames)
    }

    func testPresetsPersistAcrossStoreInstances() throws {
        let preset = LayoutPreset(name: "Work", frames: [
            "com.apple.Safari": [WindowFrame(x: 0, y: 25, width: 2560, height: 1415)],
            "com.tinyspeck.slackmacgap": [WindowFrame(x: 2560, y: 25, width: 2560, height: 1415)],
        ])
        try store.save(presets: [preset])
        let reloaded = try LayoutStore(directory: tempDir).loadPresets()
        XCTAssertEqual(reloaded, [preset])
    }

    func testMissingFilesLoadAsDefaults() {
        XCTAssertEqual(store.loadConfig(), Config())
        XCTAssertTrue(store.loadFrames().isEmpty)
        XCTAssertTrue(store.loadPresets().isEmpty)
    }

    func testCorruptFileLoadsAsDefaults() throws {
        try Data("not json{{{".utf8).write(to: store.configURL)
        XCTAssertEqual(store.loadConfig(), Config())
    }

    func testPartialConfigFallsBackToDefaultsPerField() throws {
        let json = """
        {"rules": [{"bundleID": "com.test", "displayName": "Test",
                    "enabled": true, "mode": {"kind": "zone", "zoneID": "left-half"}}]}
        """
        try Data(json.utf8).write(to: store.configURL)
        let config = store.loadConfig()
        XCTAssertTrue(config.enabled, "missing 'enabled' should default to true")
        XCTAssertEqual(config.rules.count, 1, "rules must survive partial decode")
        XCTAssertEqual(config.zones, Zone.builtIn, "missing zones fall back to built-ins")
    }

    func testEmptyZonesListFallsBackToBuiltIns() throws {
        let json = """
        {"enabled": true, "rules": [], "zones": []}
        """
        try Data(json.utf8).write(to: store.configURL)
        XCTAssertEqual(store.loadConfig().zones, Zone.builtIn)
    }

    func testDefaultConfigIncludesBuiltInZones() {
        XCTAssertEqual(store.loadConfig().zones, Zone.builtIn)
    }
}
