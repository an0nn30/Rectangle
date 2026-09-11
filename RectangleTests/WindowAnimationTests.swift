/// WindowAnimationTests.swift

import XCTest
@testable import Rectangle

final class WindowAnimationDefaultsTests: XCTestCase {

    func testDefaultsUseTheDocumentedKeys() {
        XCTAssertEqual(Defaults.windowAnimation.key, "windowAnimation")
        XCTAssertEqual(Defaults.windowAnimationDuration.key, "windowAnimationDuration")
    }

    func testDefaultsAreRegisteredForImportAndExport() {
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimation" })
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimationDuration" })
    }
}

final class WindowAnimationGeometryTests: XCTestCase {

    func testAnimatesOnlyWhenEnabledPermittedAndMotionAllowed() {
        XCTAssertTrue(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: true, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: false, hasPermission: true, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: false, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: true, reduceMotion: true))
    }

    func testDurationIsClampedToASensibleRange() {
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(0.22), 0.22, accuracy: 0.0001)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(0), WindowAnimationGeometry.minimumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(-1), WindowAnimationGeometry.minimumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(5), WindowAnimationGeometry.maximumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(.nan), WindowAnimationGeometry.minimumDuration)
    }

    func testDerivedAndZeroWindowIdsAreNotCapturable() {
        XCTAssertTrue(WindowAnimationGeometry.isCapturable(windowId: 1234))
        XCTAssertFalse(WindowAnimationGeometry.isCapturable(windowId: 0))
        XCTAssertFalse(WindowAnimationGeometry.isCapturable(windowId: AccessibilityElement.deriveWindowId(fromElementHash: 42)))
    }

    func testOverlayCoversOnlyTheScreensTheMoveTouches() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 100, y: 100, width: 200, height: 200)]),
                       left)
        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 100, y: 100, width: 200, height: 200),
                                                                      CGRect(x: 1100, y: 100, width: 200, height: 200)]),
                       left.union(right))
    }

    func testOverlayFallsBackToEveryScreenWhenNothingIsTouched() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 5000, y: 5000, width: 10, height: 10)]),
                       left.union(right))
        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right], touching: [.null]),
                       left.union(right))
        XCTAssertTrue(WindowAnimationGeometry.overlayRect(screenFrames: [], touching: [left]).isNull)
    }

    func testGhostFrameIsRelativeToTheOverlayOrigin() {
        let overlay = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: 1100, y: 50, width: 300, height: 200)

        XCTAssertEqual(WindowAnimationGeometry.ghostFrame(frame, inOverlay: overlay),
                       CGRect(x: 100, y: 50, width: 300, height: 200))
    }

    func testMovedWindowIdsIgnoresUnchangedMissingAndNullFinalFrames() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 200, y: 0, width: 100, height: 100)
        let start: [CGWindowID: CGRect] = [1: a, 2: b, 3: a, 4: a]
        let final: [CGWindowID: CGRect] = [1: b, 2: b, 3: .null]

        XCTAssertEqual(WindowAnimationGeometry.movedWindowIds(start: start, final: final), [1])
    }
}
