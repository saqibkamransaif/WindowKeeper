import XCTest
@testable import WindowKeeperCore

/// Updating a preset must not silently drop apps whose windows the capture
/// can't see (another Space, minimized, hidden) while the app is running.
final class PresetMergeTests: XCTestCase {

    private func frame(_ x: Double) -> SavedFrame {
        SavedFrame(displayUUID: "D1", relX: x, relY: 0, width: 800, height: 600)
    }

    func testCapturedAppsOverwriteExistingFrames() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(99)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured,
                                                    running: ["com.a"])
        XCTAssertEqual(result.frames["com.a"], [frame(99)])
        XCTAssertTrue(result.kept.isEmpty)
    }

    func testRunningAppMissingFromCaptureKeepsExistingFrames() {
        // App is running but its window lives in another Space, so the
        // capture saw nothing — the preset entry must survive.
        let existing = ["com.a": [frame(10)], "com.hidden": [frame(20)]]
        let captured = ["com.a": [frame(11)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured,
                                                    running: ["com.a", "com.hidden"])
        XCTAssertEqual(result.frames["com.hidden"], [frame(20)])
        XCTAssertEqual(result.kept, ["com.hidden"])
    }

    func testQuitAppMissingFromCaptureIsDropped() {
        // App is no longer running: the user closed it, so an explicit
        // "update from current layout" removes it from the preset.
        let existing = ["com.a": [frame(10)], "com.quit": [frame(20)]]
        let captured = ["com.a": [frame(11)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured,
                                                    running: ["com.a"])
        XCTAssertNil(result.frames["com.quit"])
        XCTAssertTrue(result.kept.isEmpty)
    }

    func testNewlyCapturedAppIsAdded() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(10)], "com.new": [frame(30)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured,
                                                    running: ["com.a", "com.new"])
        XCTAssertEqual(result.frames["com.new"], [frame(30)])
    }
}
