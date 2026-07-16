import XCTest
@testable import WindowKeeperCore

/// A restore is only done when EVERY saved frame has a window sitting on it.
/// `restoreProgress` is what the post-apply reconciliation loop uses to decide
/// whether to create more windows, move existing ones, or declare success.
final class RestoreProgressTests: XCTestCase {

    private let left = WindowFrame(x: 0, y: 0, width: 800, height: 600)
    private let right = WindowFrame(x: 1000, y: 0, width: 800, height: 600)
    private let bottom = WindowFrame(x: 0, y: 700, width: 800, height: 600)

    func testAllWindowsInPlaceIsSatisfied() {
        let progress = LayoutEngine.restoreProgress(current: [left, right],
                                                    saved: [left, right])
        XCTAssertEqual(progress.missingWindows, 0)
        XCTAssertTrue(progress.outOfPlace.isEmpty)
        XCTAssertTrue(progress.satisfied)
    }

    func testFewerWindowsThanSavedFramesReportsMissing() {
        // Preset saved two Terminal windows; the app launched with one.
        let progress = LayoutEngine.restoreProgress(current: [left],
                                                    saved: [left, right])
        XCTAssertEqual(progress.missingWindows, 1)
        XCTAssertTrue(progress.outOfPlace.isEmpty)
        XCTAssertFalse(progress.satisfied)
    }

    func testMovedWindowIsReportedOutOfPlaceWithItsTarget() {
        let drifted = WindowFrame(x: 0, y: 30, width: 800, height: 600)
        let progress = LayoutEngine.restoreProgress(current: [drifted, right],
                                                    saved: [left, right])
        XCTAssertEqual(progress.missingWindows, 0)
        XCTAssertEqual(progress.outOfPlace.count, 1)
        XCTAssertEqual(progress.outOfPlace.first?.windowIndex, 0)
        XCTAssertEqual(progress.outOfPlace.first?.target, left)
        XCTAssertFalse(progress.satisfied)
    }

    func testSmallDriftWithinToleranceCountsAsInPlace() {
        let almost = WindowFrame(x: 1, y: 1, width: 800, height: 600)
        let progress = LayoutEngine.restoreProgress(current: [almost, right],
                                                    saved: [left, right])
        XCTAssertTrue(progress.satisfied)
    }

    func testExtraWindowBeyondSavedFramesIsIgnored() {
        let extra = WindowFrame(x: 400, y: 300, width: 900, height: 700)
        let progress = LayoutEngine.restoreProgress(current: [left, right, extra],
                                                    saved: [left, right])
        XCTAssertTrue(progress.satisfied)
    }

    func testMissingAndOutOfPlaceCombine() {
        // One window drifted, one saved frame has no window at all.
        let drifted = WindowFrame(x: 900, y: 100, width: 800, height: 600)
        let progress = LayoutEngine.restoreProgress(current: [drifted],
                                                    saved: [left, right, bottom])
        XCTAssertEqual(progress.missingWindows, 2)
        XCTAssertEqual(progress.outOfPlace.count, 1)
        XCTAssertEqual(progress.outOfPlace.first?.target, right)
        XCTAssertFalse(progress.satisfied)
    }

    func testUnreadableWindowFrameIsTreatedAsOutOfPlace() {
        // A window whose frame can't be read still holds a slot and must be
        // re-placed rather than counted as missing.
        let progress = LayoutEngine.restoreProgress(current: [left, nil],
                                                    saved: [left, right])
        XCTAssertEqual(progress.missingWindows, 0)
        XCTAssertEqual(progress.outOfPlace.count, 1)
        XCTAssertEqual(progress.outOfPlace.first?.windowIndex, 1)
        XCTAssertEqual(progress.outOfPlace.first?.target, right)
    }

    func testTitleKeyedWindowsPairWithTheirOwnSlots() {
        // Two browser-profile windows sitting on swapped positions must each
        // be sent to the slot matching their profile, not left as "in place".
        let progress = LayoutEngine.restoreProgress(
            current: [left, right],
            saved: [left, right],
            currentTitles: ["Tab - App - Work", "Tab - App - Home"],
            savedTitles: ["Doc - App - Home", "Doc - App - Work"])
        XCTAssertEqual(progress.missingWindows, 0)
        XCTAssertEqual(progress.outOfPlace.count, 2)
        XCTAssertFalse(progress.satisfied)
    }
}
