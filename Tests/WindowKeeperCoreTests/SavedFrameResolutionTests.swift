import XCTest
@testable import WindowKeeperCore

/// Regression tests for the display-arrangement bug: frames stored as absolute
/// coordinates broke whenever a monitor was unplugged or the primary display
/// changed. Saved frames are now display-relative and must survive that.
final class SavedFrameResolutionTests: XCTestCase {

    // The user's original arrangement: 2560x1440 primary, ultra-wide to its
    // left (AX x range -5120..0), laptop far left.
    let ultrawideUUID = "UW-0001"
    let mainUUID = "MAIN-0001"
    let laptopUUID = "LAP-0001"

    var threeDisplayArrangement: [DisplayInfo] {
        [
            DisplayInfo(uuid: mainUUID, isMain: true,
                        visibleTopLeftAX: CGPoint(x: 0, y: 30),
                        visibleSize: CGSize(width: 2560, height: 1410)),
            DisplayInfo(uuid: ultrawideUUID, isMain: false,
                        visibleTopLeftAX: CGPoint(x: -5120, y: 30),
                        visibleSize: CGSize(width: 5120, height: 1410)),
            DisplayInfo(uuid: laptopUUID, isMain: false,
                        visibleTopLeftAX: CGPoint(x: -6616, y: 106),
                        visibleSize: CGSize(width: 1496, height: 939)),
        ]
    }

    // After unplugging the 2560 monitor: ultra-wide becomes primary (x 0..5120),
    // laptop sits to its left.
    var twoDisplayArrangement: [DisplayInfo] {
        [
            DisplayInfo(uuid: ultrawideUUID, isMain: true,
                        visibleTopLeftAX: CGPoint(x: 0, y: 63),
                        visibleSize: CGSize(width: 5120, height: 1347)),
            DisplayInfo(uuid: laptopUUID, isMain: false,
                        visibleTopLeftAX: CGPoint(x: -1496, y: 106),
                        visibleSize: CGSize(width: 1496, height: 939)),
        ]
    }

    // MARK: - Capture

    func testMakeSavedUsesDisplayContainingWindowCenter() {
        // Window on the ultra-wide in the 3-display arrangement.
        let frame = WindowFrame(x: -5120, y: 30, width: 1182, height: 1347)
        let saved = LayoutEngine.makeSaved(from: frame, displays: threeDisplayArrangement)
        XCTAssertEqual(saved.displayUUID, ultrawideUUID)
        XCTAssertEqual(saved.relX, 0)   // at the display's left edge
        XCTAssertEqual(saved.relY, 0)   // at the display's visible top
        XCTAssertEqual(saved.width, 1182)
        XCTAssertEqual(saved.height, 1347)
    }

    func testMakeSavedFallsBackToMainForOffscreenWindow() {
        let frame = WindowFrame(x: 99999, y: 99999, width: 500, height: 400)
        let saved = LayoutEngine.makeSaved(from: frame, displays: threeDisplayArrangement)
        XCTAssertEqual(saved.displayUUID, mainUUID)
    }

    // MARK: - The core regression: arrangement changes

    func testFrameSavedOnUltrawideResolvesAfterArrangementChange() {
        // Capture on the OLD arrangement…
        let original = WindowFrame(x: -5120, y: 30, width: 1182, height: 1347)
        let saved = LayoutEngine.makeSaved(from: original, displays: threeDisplayArrangement)

        // …resolve on the NEW arrangement where the ultra-wide is primary.
        let resolved = LayoutEngine.resolve(saved: saved, displays: twoDisplayArrangement)

        // Same display (by UUID), same relative spot: its new left edge/top.
        XCTAssertEqual(resolved, WindowFrame(x: 0, y: 63, width: 1182, height: 1347))
    }

    func testRoundTripOnSameArrangementIsExact() {
        let original = WindowFrame(x: -3000, y: 400, width: 800, height: 600)
        let saved = LayoutEngine.makeSaved(from: original, displays: threeDisplayArrangement)
        let resolved = LayoutEngine.resolve(saved: saved, displays: threeDisplayArrangement)
        XCTAssertEqual(resolved, original)
    }

    func testMissingDisplayFallsBackToMainKeepingOffset() {
        let saved = SavedFrame(displayUUID: "GONE-9999", relX: 100, relY: 50,
                               width: 900, height: 700)
        let resolved = LayoutEngine.resolve(saved: saved, displays: twoDisplayArrangement)
        // Main is the ultra-wide: visible top-left (0, 63) + offset (100, 50).
        XCTAssertEqual(resolved, WindowFrame(x: 100, y: 113, width: 900, height: 700))
    }

    // MARK: - Legacy absolute frames (v1.0 files)

    func testLegacyFrameStillOnADisplayIsKeptInPlace() {
        // Absolute frame that happens to still be valid in the new arrangement.
        let saved = SavedFrame(displayUUID: nil, relX: 200, relY: 100,
                               width: 1000, height: 800)
        let resolved = LayoutEngine.resolve(saved: saved, displays: twoDisplayArrangement)
        XCTAssertEqual(resolved, WindowFrame(x: 200, y: 100, width: 1000, height: 800))
    }

    func testLegacyFrameFromDeadArrangementClampsIntoMainDisplay() {
        // The user's exact stale preset frame: x=-5120 no longer exists.
        let saved = SavedFrame(displayUUID: nil, relX: -5120, relY: 30,
                               width: 1182, height: 1347)
        let resolved = LayoutEngine.resolve(saved: saved, displays: twoDisplayArrangement)
        let frame = try! XCTUnwrap(resolved)
        // Must land fully inside the main display's visible area.
        let main = twoDisplayArrangement[0].visibleRect
        XCTAssertTrue(main.contains(frame.rect),
                      "resolved frame \(frame) must be inside main visible \(main)")
        // Size preserved (it fits).
        XCTAssertEqual(frame.width, 1182)
        XCTAssertEqual(frame.height, 1347)
    }

    // MARK: - Clamping

    func testOversizedFrameShrinksToVisibleArea() {
        let display = twoDisplayArrangement[1] // laptop 1496x939
        let huge = WindowFrame(x: -1496, y: 106, width: 3000, height: 2000)
        let clamped = LayoutEngine.clamp(huge, into: display)
        XCTAssertEqual(clamped.width, 1496)
        XCTAssertEqual(clamped.height, 939)
        XCTAssertTrue(display.visibleRect.contains(clamped.rect))
    }

    func testFramePartiallyOffDisplayIsShiftedInside() {
        let display = twoDisplayArrangement[0] // ultra-wide, visible x 0..5120
        let hangingOff = WindowFrame(x: 4800, y: 63, width: 800, height: 600)
        let clamped = LayoutEngine.clamp(hangingOff, into: display)
        XCTAssertEqual(clamped.x, 4320) // 5120 - 800
        XCTAssertEqual(clamped.width, 800)
        XCTAssertTrue(display.visibleRect.contains(clamped.rect))
    }

    func testResolveWithNoDisplaysReturnsNil() {
        let saved = SavedFrame(displayUUID: ultrawideUUID, relX: 0, relY: 0,
                               width: 800, height: 600)
        XCTAssertNil(LayoutEngine.resolve(saved: saved, displays: []))
    }
}
