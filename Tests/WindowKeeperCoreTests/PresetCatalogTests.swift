import XCTest
@testable import WindowKeeperCore

/// The default preset is what the top-of-menu "Restore" button and the
/// ⌥⌘R send-back shortcut use. Preferences can rename presets, so names are
/// validated in one place.
final class PresetCatalogTests: XCTestCase {

    private let a = LayoutPreset(id: "A", name: "Work", frames: [:])
    private let b = LayoutPreset(id: "B", name: "My Setup", frames: [:])

    func testChosenDefaultWins() {
        XCTAssertEqual(PresetCatalog.defaultPreset(in: [a, b], defaultID: "A")?.id, "A")
    }

    func testMissingDefaultFallsBackToNewestPreset() {
        XCTAssertEqual(PresetCatalog.defaultPreset(in: [a, b], defaultID: "gone")?.id, "B")
        XCTAssertEqual(PresetCatalog.defaultPreset(in: [a, b], defaultID: nil)?.id, "B")
    }

    func testNoPresetsMeansNoDefault() {
        XCTAssertNil(PresetCatalog.defaultPreset(in: [], defaultID: "A"))
    }

    func testRenameTrimsAndReturnsNewList() {
        let renamed = PresetCatalog.renaming([a, b], id: "A", to: "  Focus  ")
        XCTAssertEqual(renamed?.map(\.name), ["Focus", "My Setup"])
        XCTAssertEqual(a.name, "Work", "original list must not change")
    }

    func testRenameRejectsBlankNameAndUnknownID() {
        XCTAssertNil(PresetCatalog.renaming([a, b], id: "A", to: "   "))
        XCTAssertNil(PresetCatalog.renaming([a, b], id: "nope", to: "Focus"))
    }

    func testCleanNameFallsBackWhenBlank() {
        XCTAssertEqual(PresetCatalog.cleanName("  ", fallback: "My Setup"), "My Setup")
        XCTAssertEqual(PresetCatalog.cleanName(" Deep Work ", fallback: "x"), "Deep Work")
    }
}
