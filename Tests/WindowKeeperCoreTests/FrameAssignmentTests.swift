import XCTest
@testable import WindowKeeperCore

/// Windows must be matched to saved frames by proximity, not list order.
/// macOS returns windows in z-order, so activating a different window (e.g.
/// switching browser profiles) used to remap every frame and shuffle windows.
final class FrameAssignmentTests: XCTestCase {

    private let left = WindowFrame(x: 0, y: 0, width: 800, height: 600)
    private let right = WindowFrame(x: 1000, y: 0, width: 800, height: 600)
    private let bottom = WindowFrame(x: 0, y: 700, width: 800, height: 600)

    func testWindowsAlreadyOnSavedFramesKeepThemRegardlessOfOrder() {
        // Same two windows, reported in reversed z-order: nothing should move.
        let targets = LayoutEngine.assignTargets(current: [right, left],
                                                 saved: [left, right])
        XCTAssertEqual(targets, [right, left])
    }

    func testMovedWindowReturnsToItsNearestSavedFrame() {
        // The left window was dragged a bit; the right one stayed put. The
        // moved window must get the left frame back, not swap with the other.
        let draggedLeft = WindowFrame(x: 150, y: 80, width: 800, height: 600)
        let targets = LayoutEngine.assignTargets(current: [draggedLeft, right],
                                                 saved: [left, right])
        XCTAssertEqual(targets, [left, right])
    }

    func testExtraWindowBeyondSavedFramesIsLeftAlone() {
        // A third (e.g. new profile) window with no saved slot stays put.
        let newWindow = WindowFrame(x: 500, y: 300, width: 900, height: 700)
        let targets = LayoutEngine.assignTargets(current: [newWindow, left, right],
                                                 saved: [left, right])
        XCTAssertEqual(targets, [nil, left, right])
    }

    func testInPlaceWindowIsNotStolenByACloserMovedWindow() {
        // A window sits exactly on its saved frame; another window was moved
        // right next to that frame. The in-place window keeps its claim.
        let hoveringNearLeft = WindowFrame(x: 20, y: 10, width: 800, height: 600)
        let targets = LayoutEngine.assignTargets(current: [hoveringNearLeft, left],
                                                 saved: [left, bottom])
        XCTAssertEqual(targets, [bottom, left])
    }

    func testUnreadableWindowFrameTakesALeftoverSlot() {
        let targets = LayoutEngine.assignTargets(current: [left, nil],
                                                 saved: [left, right])
        XCTAssertEqual(targets, [left, right])
    }

    func testMoreSavedFramesThanWindowsAssignsNearest() {
        // One window, several saved slots (others' windows were closed):
        // it goes to the closest slot, the rest are ignored.
        let nearBottom = WindowFrame(x: 40, y: 650, width: 800, height: 600)
        let targets = LayoutEngine.assignTargets(current: [nearBottom],
                                                 saved: [left, right, bottom])
        XCTAssertEqual(targets, [bottom])
    }

    func testNoSavedFramesLeavesAllWindowsAlone() {
        let targets = LayoutEngine.assignTargets(current: [left, right], saved: [])
        XCTAssertEqual(targets, [nil, nil])
    }

    func testNoWindowsProducesNoTargets() {
        XCTAssertTrue(LayoutEngine.assignTargets(current: [], saved: [left]).isEmpty)
    }

    // MARK: - Title-aware matching (browser profiles, documents)

    func testTitledSlotGoesToItsWindowEvenWhenAnotherIsCloser() {
        // The personal profile wandered to the far side; a different profile
        // now sits nearest the saved slot. The slot's title must win.
        let farAway = WindowFrame(x: 2000, y: 900, width: 900, height: 700)
        let nearSlot = WindowFrame(x: 30, y: 20, width: 800, height: 600)
        let targets = LayoutEngine.assignTargets(
            current: [nearSlot, farAway],
            saved: [left],
            currentTitles: ["Some Tab - Comet - Sarah",
                            "Perplexity - Comet - Saqib Kamran"],
            savedTitles: ["Comet - Saqib Kamran"])
        XCTAssertEqual(targets, [nil, left])
    }

    func testTitleKeyIsLastDashSeparatedToken() {
        // Tab part changes between capture and restore; only the trailing
        // profile token has to agree (both "-" and "–" separators appear).
        let targets = LayoutEngine.assignTargets(
            current: [bottom],
            saved: [left],
            currentTitles: ["News – Today - Comet - Saqib Kamran"],
            savedTitles: ["Old Tab - Comet - Saqib Kamran"])
        XCTAssertEqual(targets, [left])
    }

    func testUnmatchedTitlesFallBackToProximity() {
        let targets = LayoutEngine.assignTargets(
            current: [left, right],
            saved: [left, right],
            currentTitles: ["Doc A", "Doc B"],
            savedTitles: ["Doc C", "Doc D"])
        XCTAssertEqual(targets, [left, right])
    }

    func testDuplicateTitleKeysMatchWithinGroupByProximity() {
        // Two windows of the same profile: match inside the group by
        // position, and don't leak its slots to other profiles.
        let movedA = WindowFrame(x: 60, y: 40, width: 800, height: 600)
        let targets = LayoutEngine.assignTargets(
            current: [movedA, right, bottom],
            saved: [left, right, bottom],
            currentTitles: ["A - Comet - Work", "B - Comet - Work",
                            "C - Comet - Personal"],
            savedTitles: ["X - Comet - Work", "Y - Comet - Work",
                          "Z - Comet - Personal"])
        XCTAssertEqual(targets, [left, right, bottom])
    }

    func testTitledSlotNeverGrabsAWindowWithADifferentKnownTitle() {
        // The titled window is gone (profile closed). A window that clearly
        // belongs to ANOTHER profile must not be yanked into the slot.
        let targets = LayoutEngine.assignTargets(
            current: [bottom],
            saved: [left],
            currentTitles: ["Tab - Comet - Sarah"],
            savedTitles: ["Tab - Comet - Saqib Kamran"])
        XCTAssertEqual(targets, [nil])
    }

    func testUntitledWindowMayFillATitledSlot() {
        // Unknown identity (no title readable): behave like before titles
        // existed, so title drift can't strand a slot forever.
        let targets = LayoutEngine.assignTargets(
            current: [bottom],
            saved: [left],
            currentTitles: [nil],
            savedTitles: ["Tab - Comet - Saqib Kamran"])
        XCTAssertEqual(targets, [left])
    }
}
