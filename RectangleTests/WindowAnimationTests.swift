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

final class WindowSnapshotTests: XCTestCase {

    func testBackdropKeepsFrontToBackOrderAndDropsExcludedWindows() {
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [50, 40, 30, 20], excluding: [40, 20]), [50, 30])
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [50, 40], excluding: []), [50, 40])
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [], excluding: [1]), [])
    }
}

/// A tiny opaque image for tests that need a CGImage.
func makeTestImage(width: Int = 4, height: Int = 4) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

final class GhostOverlayWindowTests: XCTestCase {

    func testOverlayNeverTakesFocusOrMouseInput() {
        let overlay = GhostOverlayWindow()

        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.canBecomeKey)
        XCTAssertFalse(overlay.hidesOnDeactivate)
        XCTAssertFalse(overlay.hasShadow)
        XCTAssertEqual(overlay.level, .floating)
        XCTAssertTrue(overlay.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertGreaterThan(overlay.overlayWindowId, 0)
    }

    func testPresentShowsGhostsAndDismissClearsThem() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 7, image: makeTestImage(), startFrame: CGRect(x: 10, y: 10, width: 40, height: 40))

        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: makeTestImage(), ghosts: [ghost])
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 1)

        overlay.addGhost(GhostSpec(id: 8, image: makeTestImage(), startFrame: CGRect(x: 60, y: 10, width: 40, height: 40)))
        XCTAssertEqual(overlay.ghostCount, 2)

        overlay.dismiss()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
        XCTAssertEqual(overlay.alphaValue, 1)
    }

    func testAnimateDropsGhostsThatAreNotMovingAndCompletes() {
        let overlay = GhostOverlayWindow()
        let moving = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let still = GhostSpec(id: 2, image: makeTestImage(), startFrame: CGRect(x: 100, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [moving, still])

        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [2], duration: 0.05) {
            completed.fulfill()
        }
        XCTAssertEqual(overlay.ghostCount, 1)

        wait(for: [completed], timeout: 2)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
    }

    func testDismissDuringAnimationCancelsFadeAndResetsAlpha() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])

        let completed = expectation(description: "animation completed")
        completed.isInverted = true
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: 1.0) {
            completed.fulfill()
        }

        // Let the fade actually start (it begins at fadeStartFraction * duration = 0.65s) before interrupting
        // it, so this exercises dismiss() racing a genuinely in-flight animator-driven fade, not merely a
        // scheduled one the generation guard would skip before it ever ran.
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        overlay.dismiss()

        // Wait past the original fade's natural end (~1.0s) so an animation that wasn't actually cancelled
        // has time to settle back to alpha 0 before we check it.
        wait(for: [completed], timeout: 0.4)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
        XCTAssertEqual(overlay.alphaValue, 1)
    }
}
