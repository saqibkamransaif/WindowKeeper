import XCTest
@testable import WindowKeeperCore

final class LayoutEngineTests: XCTestCase {

    // Ultra-wide primary display: 5120x1440, menu bar eats 25pt off the top.
    let ultrawideVisible = CGRect(x: 0, y: 0, width: 5120, height: 1415)
    let primaryHeight: CGFloat = 1440

    // MARK: - Coordinate conversion

    func testCocoaToAXConversion() {
        // A window at the bottom-left of a 1440-high screen in Cocoa coords.
        let cocoa = CGRect(x: 100, y: 0, width: 800, height: 600)
        let ax = LayoutEngine.axFrame(fromCocoa: cocoa, primaryHeight: 1440)
        XCTAssertEqual(ax.x, 100)
        XCTAssertEqual(ax.y, 840) // 1440 - 0 - 600
        XCTAssertEqual(ax.width, 800)
        XCTAssertEqual(ax.height, 600)
    }

    func testAXToCocoaRoundTrip() {
        let original = CGRect(x: 250, y: 315, width: 1280, height: 720)
        let ax = LayoutEngine.axFrame(fromCocoa: original, primaryHeight: 1440)
        let back = LayoutEngine.cocoaRect(fromAX: ax, primaryHeight: 1440)
        XCTAssertEqual(back, original)
    }

    // MARK: - Zone resolution on an ultra-wide screen

    func testLeftHalfZoneOnUltrawide() {
        let zone = Zone.builtIn.first { $0.id == "left-half" }!
        let frame = LayoutEngine.resolve(zone: zone,
                                         visibleFrame: ultrawideVisible,
                                         primaryHeight: primaryHeight)
        XCTAssertEqual(frame.x, 0)
        XCTAssertEqual(frame.y, 25) // below the menu bar
        XCTAssertEqual(frame.width, 2560)
        XCTAssertEqual(frame.height, 1415)
    }

    func testMiddleThirdZoneOnUltrawide() {
        let zone = Zone.builtIn.first { $0.id == "middle-third" }!
        let frame = LayoutEngine.resolve(zone: zone,
                                         visibleFrame: ultrawideVisible,
                                         primaryHeight: primaryHeight)
        XCTAssertEqual(frame.x, 5120.0 / 3, accuracy: 0.5)
        XCTAssertEqual(frame.width, 5120.0 / 3, accuracy: 0.5)
        XCTAssertEqual(frame.height, 1415)
    }

    func testRightTwoThirdsZoneOnUltrawide() {
        let zone = Zone.builtIn.first { $0.id == "right-two-thirds" }!
        let frame = LayoutEngine.resolve(zone: zone,
                                         visibleFrame: ultrawideVisible,
                                         primaryHeight: primaryHeight)
        XCTAssertEqual(frame.x, 5120.0 / 3, accuracy: 0.5)
        XCTAssertEqual(frame.width, 5120.0 * 2 / 3, accuracy: 0.5)
        // Right edge must land on the screen edge.
        XCTAssertEqual(frame.x + frame.width, 5120, accuracy: 1.0)
    }

    func testZoneOnSecondaryDisplayOffsets() {
        // Secondary display to the right of the primary, smaller, own visible frame.
        let secondaryVisible = CGRect(x: 5120, y: 200, width: 1920, height: 1055)
        let zone = Zone(id: "custom", name: "Custom", fx: 0, fy: 0, fw: 1, fh: 1,
                        displayIndex: 1)
        let frame = LayoutEngine.resolve(zone: zone,
                                         visibleFrame: secondaryVisible,
                                         primaryHeight: primaryHeight)
        XCTAssertEqual(frame.x, 5120)
        // AX y of the secondary's visible top: 1440 - (200 + 1055) = 185
        XCTAssertEqual(frame.y, 185)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1055)
    }

    func testZoneFramesLandOnHalfPointBoundaries() {
        for zone in Zone.builtIn {
            let frame = LayoutEngine.resolve(zone: zone,
                                             visibleFrame: ultrawideVisible,
                                             primaryHeight: primaryHeight)
            for value in [frame.x, frame.y, frame.width, frame.height] {
                XCTAssertEqual(value * 2, (value * 2).rounded(), accuracy: 0.001,
                               "zone \(zone.id) produced a sub-half-point value \(value)")
            }
        }
    }

    // MARK: - Frame matching

    func testFramesMatchWithinTolerance() {
        let a = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let b = WindowFrame(x: 101.5, y: 99, width: 801, height: 598.5)
        XCTAssertTrue(LayoutEngine.framesMatch(a, b))
    }

    func testFramesDoNotMatchOutsideTolerance() {
        let a = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let b = WindowFrame(x: 104, y: 100, width: 800, height: 600)
        XCTAssertFalse(LayoutEngine.framesMatch(a, b))
    }

    // MARK: - Target frame planning

    func testRememberModeAppliesSavedFramesByOrder() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test")
        let saved = [WindowFrame(x: 0, y: 0, width: 100, height: 100),
                     WindowFrame(x: 200, y: 0, width: 100, height: 100)]
        let targets = LayoutEngine.targetFrames(rule: rule, windowCount: 2,
                                                remembered: saved,
                                                zoneResolver: { _ in nil })
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0], saved[0])
        XCTAssertEqual(targets[1], saved[1])
    }

    func testRememberModeExtraWindowsReuseLastFrame() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test")
        let saved = [WindowFrame(x: 0, y: 0, width: 100, height: 100)]
        let targets = LayoutEngine.targetFrames(rule: rule, windowCount: 3,
                                                remembered: saved,
                                                zoneResolver: { _ in nil })
        XCTAssertEqual(targets.count, 3)
        XCTAssertTrue(targets.allSatisfy { $0 == saved[0] })
    }

    func testRememberModeWithNothingSavedLeavesWindowsAlone() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test")
        let targets = LayoutEngine.targetFrames(rule: rule, windowCount: 2,
                                                remembered: nil,
                                                zoneResolver: { _ in nil })
        XCTAssertEqual(targets.count, 2)
        XCTAssertTrue(targets.allSatisfy { $0 == nil })
    }

    func testZoneModeSnapsEveryWindowToZone() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test",
                           mode: .zone("left-half"))
        let zoneFrame = WindowFrame(x: 0, y: 25, width: 2560, height: 1415)
        let targets = LayoutEngine.targetFrames(rule: rule, windowCount: 3,
                                                remembered: nil,
                                                zoneResolver: { id in
                                                    id == "left-half" ? zoneFrame : nil
                                                })
        XCTAssertEqual(targets.count, 3)
        XCTAssertTrue(targets.allSatisfy { $0 == zoneFrame })
    }

    func testZeroWindowsProducesNoTargets() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test")
        let targets = LayoutEngine.targetFrames(rule: rule, windowCount: 0,
                                                remembered: nil,
                                                zoneResolver: { _ in nil })
        XCTAssertTrue(targets.isEmpty)
    }
}
