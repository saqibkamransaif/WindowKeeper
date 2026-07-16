import XCTest
@testable import WindowKeeperCore

/// Updating a preset must never silently drop an app. The capture only sees
/// windows on the current Space, and apps that aren't running have no windows
/// at all — both used to fall out of the preset on "Update from current
/// layout", and a later restore then "ignored" them (this is exactly how
/// ChatGPT and Perplexity vanished from a daily-driver preset). An update
/// refreshes what it can see and keeps the rest; removing an app is an
/// explicit act (save a fresh preset), not a side effect.
final class PresetMergeTests: XCTestCase {

    private func frame(_ x: Double) -> SavedFrame {
        SavedFrame(displayUUID: "D1", relX: x, relY: 0, width: 800, height: 600)
    }

    func testCapturedAppsOverwriteExistingFrames() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(99)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured)
        XCTAssertEqual(result.frames["com.a"], [frame(99)])
        XCTAssertTrue(result.kept.isEmpty)
    }

    func testRunningAppMissingFromCaptureKeepsExistingFrames() {
        // App is running but its window lives in another Space, so the
        // capture saw nothing — the preset entry must survive.
        let existing = ["com.a": [frame(10)], "com.hidden": [frame(20)]]
        let captured = ["com.a": [frame(11)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured)
        XCTAssertEqual(result.frames["com.hidden"], [frame(20)])
        XCTAssertEqual(result.kept, ["com.hidden"])
    }

    func testQuitAppMissingFromCaptureIsKept() {
        // App isn't running at update time. It is still part of the layout —
        // the next restore must launch and place it, so it stays.
        let existing = ["com.a": [frame(10)], "com.quit": [frame(20)]]
        let captured = ["com.a": [frame(11)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured)
        XCTAssertEqual(result.frames["com.quit"], [frame(20)])
        XCTAssertEqual(result.kept, ["com.quit"])
    }

    func testNewlyCapturedAppIsAdded() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(10)], "com.new": [frame(30)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured)
        XCTAssertEqual(result.frames["com.new"], [frame(30)])
    }

    func testKeptListIsSortedAndCoversEveryPreservedApp() {
        let existing = ["com.b": [frame(1)], "com.a": [frame(2)], "com.c": [frame(3)]]
        let captured = ["com.c": [frame(4)]]
        let result = LayoutEngine.mergePresetFrames(existing: existing,
                                                    captured: captured)
        XCTAssertEqual(result.kept, ["com.a", "com.b"])
        XCTAssertEqual(result.frames.count, 3)
    }
}
