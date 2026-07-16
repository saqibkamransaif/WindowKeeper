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
}
