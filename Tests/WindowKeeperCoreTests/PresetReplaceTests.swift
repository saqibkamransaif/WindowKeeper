import XCTest
@testable import WindowKeeperCore

/// "Update from Current Layout" saves exactly what is on screen. It used to
/// merge: every app the capture missed kept its old frames, so a user who
/// closed apps and re-saved got those apps relaunched at their old places on
/// the next restore ("it restored the original one"). An update now replaces
/// the preset's frames with the capture and reports what it removed — except
/// an empty capture, which must never wipe a preset.
final class PresetReplaceTests: XCTestCase {

    private func frame(_ x: Double) -> SavedFrame {
        SavedFrame(displayUUID: "D1", relX: x, relY: 0, width: 800, height: 600)
    }

    func testCapturedAppsOverwriteExistingFrames() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(99)]]
        let result = LayoutEngine.replacePresetFrames(existing: existing,
                                                      captured: captured)
        XCTAssertEqual(result.frames, ["com.a": [frame(99)]])
        XCTAssertTrue(result.removed.isEmpty)
    }

    func testAppMissingFromCaptureIsRemoved() {
        // Closed (or windowless) at update time: not part of the layout on
        // screen, so the next restore must not relaunch it.
        let existing = ["com.a": [frame(10)], "com.closed": [frame(20)]]
        let captured = ["com.a": [frame(11)]]
        let result = LayoutEngine.replacePresetFrames(existing: existing,
                                                      captured: captured)
        XCTAssertNil(result.frames["com.closed"])
        XCTAssertEqual(result.removed, ["com.closed"])
    }

    func testNewlyCapturedAppIsAdded() {
        let existing = ["com.a": [frame(10)]]
        let captured = ["com.a": [frame(10)], "com.new": [frame(30)]]
        let result = LayoutEngine.replacePresetFrames(existing: existing,
                                                      captured: captured)
        XCTAssertEqual(result.frames["com.new"], [frame(30)])
        XCTAssertTrue(result.removed.isEmpty)
    }

    func testRemovedListIsSortedAndFramesEqualCapture() {
        let existing = ["com.b": [frame(1)], "com.a": [frame(2)], "com.c": [frame(3)]]
        let captured = ["com.c": [frame(4)]]
        let result = LayoutEngine.replacePresetFrames(existing: existing,
                                                      captured: captured)
        XCTAssertEqual(result.removed, ["com.a", "com.b"])
        XCTAssertEqual(result.frames, captured)
    }

    func testEmptyCaptureLeavesPresetUntouched() {
        // Nothing visible (screen locked, Accessibility revoked): wiping the
        // preset would destroy the layout, so keep it and remove nothing.
        let existing = ["com.a": [frame(10)], "com.b": [frame(20)]]
        let result = LayoutEngine.replacePresetFrames(existing: existing,
                                                      captured: [:])
        XCTAssertEqual(result.frames, existing)
        XCTAssertTrue(result.removed.isEmpty)
    }
}
