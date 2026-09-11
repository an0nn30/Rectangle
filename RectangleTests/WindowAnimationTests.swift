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

    func testEarlyContentWaitsForThePlannedCrossfadeWindow() {
        let duration = 0.26
        let timing = WindowAnimationGeometry.crossfadeTiming(elapsed: 0.033, duration: duration)

        XCTAssertEqual(timing.delay, duration * WindowAnimationGeometry.crossfadeStartFraction - 0.033, accuracy: 1e-9)
        XCTAssertEqual(timing.length,
                       duration * (WindowAnimationGeometry.crossfadeEndFraction - WindowAnimationGeometry.crossfadeStartFraction),
                       accuracy: 1e-9)
    }

    func testLateContentCrossfadesAtOnceForAtLeastTheMinimumLength() {
        let duration = 0.26
        let insideWindow = duration * 0.3
        let pastWindow = duration * 0.9

        let inside = WindowAnimationGeometry.crossfadeTiming(elapsed: insideWindow, duration: duration)
        XCTAssertEqual(inside.delay, 0)
        XCTAssertEqual(inside.length, max(WindowAnimationGeometry.minimumCrossfadeDuration,
                                          duration * WindowAnimationGeometry.crossfadeEndFraction - insideWindow),
                       accuracy: 1e-9)

        let late = WindowAnimationGeometry.crossfadeTiming(elapsed: pastWindow, duration: duration)
        XCTAssertEqual(late.delay, 0)
        XCTAssertEqual(late.length, WindowAnimationGeometry.minimumCrossfadeDuration, accuracy: 1e-9)
    }

    func testSettledCaptureMustMatchTheNewSizeAtAWholeBackingScale() {
        let newSize = CGSize(width: 861, height: 507)

        XCTAssertTrue(WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: 1722, height: 1014), frameSize: newSize))
        XCTAssertTrue(WindowAnimationGeometry.isSettledCapture(imageSize: newSize, frameSize: newSize))
        XCTAssertTrue(WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: 1723, height: 1013), frameSize: newSize),
                      "a pixel of rounding either way is fine")
        XCTAssertFalse(WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: 894, height: 780), frameSize: newSize),
                       "the old 447x390 backing store at 2x has not been redrawn yet")
        XCTAssertFalse(WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: 1722, height: 900), frameSize: newSize))
        XCTAssertFalse(WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: 4, height: 4), frameSize: newSize))
        XCTAssertFalse(WindowAnimationGeometry.isSettledCapture(imageSize: newSize, frameSize: .zero))
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

    func testBackdropCandidatesDropRectanglesOwnWindowsAndEntriesWithoutANumber() {
        let infos: [[String: Any]] = [
            [kCGWindowNumber as String: NSNumber(value: 50), kCGWindowOwnerPID as String: NSNumber(value: 200)],
            // Rectangle's own panels (the drag-to-snap footprint, the overlay) must not be composited in.
            [kCGWindowNumber as String: NSNumber(value: 40), kCGWindowOwnerPID as String: NSNumber(value: 99)],
            [kCGWindowOwnerPID as String: NSNumber(value: 200)],
            [kCGWindowNumber as String: NSNumber(value: 30)],
        ]

        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: infos, ownPid: 99, maximumLayer: 3), [50, 30])
        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: infos, ownPid: 1, maximumLayer: 3), [50, 40, 30])
        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: [], ownPid: 99, maximumLayer: 3), [])
    }

    func testBackdropCandidatesDropWindowsDrawnAboveTheOverlay() {
        // The Dock, the menu bar and its items are drawn live above the overlay. Baked into the backdrop
        // as well, they would show through their own translucent glass as a smeared second copy.
        let window = { (number: Int, layer: Int) -> [String: Any] in
            [kCGWindowNumber as String: NSNumber(value: number),
             kCGWindowOwnerPID as String: NSNumber(value: 200),
             kCGWindowLayer as String: NSNumber(value: layer)]
        }
        let infos = [window(1, 25), window(2, 24), window(3, 20), window(7, 4), window(4, 3), window(5, 0),
                     window(6, Int(CGWindowLevelForKey(.desktopWindow)))]

        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: infos, ownPid: 99, maximumLayer: 3), [4, 5, 6])
        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: infos, ownPid: 99, maximumLayer: 20), [3, 7, 4, 5, 6])
    }

    func testBackdropDropsDockGlassButKeepsWallpaperOwnedByTheSameProcess() {
        // macOS 26 reports both the glass Dock and a wallpaper window under the Dock's PID.
        // Filtering by owner instead of layer would remove the wallpaper as well.
        let dockPid = 200
        let infos: [[String: Any]] = [
            [kCGWindowNumber as String: 13, kCGWindowOwnerPID as String: dockPid,
             kCGWindowLayer as String: CGWindowLevelForKey(.dockWindow)],
            [kCGWindowNumber as String: 40, kCGWindowOwnerPID as String: 300,
             kCGWindowLayer as String: NSWindow.Level.normal.rawValue],
            [kCGWindowNumber as String: 1275, kCGWindowOwnerPID as String: dockPid,
             kCGWindowLayer as String: CGWindowLevelForKey(.desktopWindow)],
        ]

        XCTAssertEqual(WindowSnapshot.backdropCandidateIds(from: infos, ownPid: 99,
                                                           maximumLayer: WindowSnapshot.defaultMaximumLayer), [40, 1275])
        let overlay = GhostOverlayWindow()
        XCTAssertLessThan(overlay.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)))
        XCTAssertEqual(WindowSnapshot.defaultMaximumLayer, overlay.level.rawValue)
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

    func testGhostsKeepWindowServerOrderInsteadOfCallerOrder() throws {
        let overlay = GhostOverlayWindow(windowOrder: { [1, 2, 3] })
        defer { overlay.dismiss() }
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ghosts = [1, 3, 2].map { GhostSpec(id: CGWindowID($0), image: makeTestImage(), startFrame: frame) }

        overlay.present(overlayFrame: frame, backdrop: makeTestImage(), ghosts: ghosts)

        let front = try XCTUnwrap(overlay.ghostLayer(1))
        let middle = try XCTUnwrap(overlay.ghostLayer(2))
        let back = try XCTUnwrap(overlay.ghostLayer(3))
        let backdrop = try XCTUnwrap(overlay.contentView?.layer?.sublayers?.first)
        XCTAssertGreaterThan(front.zPosition, middle.zPosition)
        XCTAssertGreaterThan(middle.zPosition, back.zPosition)
        XCTAssertGreaterThan(back.zPosition, backdrop.zPosition)
    }

    func testLaterGhostsAndCrossfadesKeepTheOrderCapturedBeforeTheMove() throws {
        var order: [CGWindowID] = [1, 2, 3]
        let overlay = GhostOverlayWindow(windowOrder: { order })
        defer { overlay.dismiss() }
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        overlay.present(overlayFrame: frame, backdrop: nil,
                        ghosts: [GhostSpec(id: 1, image: makeTestImage(), startFrame: frame)])

        // Moving real windows can raise them. Late cooperative additions still belong to the original stack.
        order = [3, 2, 1]
        overlay.addGhost(GhostSpec(id: 3, image: makeTestImage(), startFrame: frame))
        overlay.addGhost(GhostSpec(id: 2, image: makeTestImage(), startFrame: frame))
        overlay.animate(endFrames: [1: frame, 2: frame, 3: frame], removing: [], duration: 0.3) {}
        overlay.crossfade(ghost: 2, to: makeTestImage())

        let front = try XCTUnwrap(overlay.ghostLayer(1))
        let middle = try XCTUnwrap(overlay.ghostLayer(2))
        let back = try XCTUnwrap(overlay.ghostLayer(3))
        let settled = try XCTUnwrap(overlay.settledLayer(2))
        XCTAssertGreaterThan(front.zPosition, middle.zPosition)
        XCTAssertGreaterThan(middle.zPosition, back.zPosition)
        XCTAssertEqual(settled.zPosition, middle.zPosition)
        XCTAssertGreaterThan(front.zPosition, settled.zPosition)
        XCTAssertGreaterThan(settled.zPosition, back.zPosition)
    }

    func testNewPresentationRefreshesWindowOrderAndKeepsUnknownGhostAboveBackdrop() throws {
        var order: [CGWindowID] = [1, 2]
        let overlay = GhostOverlayWindow(windowOrder: { order })
        defer { overlay.dismiss() }
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ghosts = [1, 2, 99].map { GhostSpec(id: CGWindowID($0), image: makeTestImage(), startFrame: frame) }
        overlay.present(overlayFrame: frame, backdrop: makeTestImage(), ghosts: ghosts)
        XCTAssertGreaterThan(try XCTUnwrap(overlay.ghostLayer(1)).zPosition,
                             try XCTUnwrap(overlay.ghostLayer(2)).zPosition)

        order = [2, 1]
        overlay.present(overlayFrame: frame, backdrop: makeTestImage(), ghosts: ghosts)

        XCTAssertGreaterThan(try XCTUnwrap(overlay.ghostLayer(2)).zPosition,
                             try XCTUnwrap(overlay.ghostLayer(1)).zPosition)
        XCTAssertGreaterThan(try XCTUnwrap(overlay.ghostLayer(99)).zPosition,
                             try XCTUnwrap(overlay.contentView?.layer?.sublayers?.first).zPosition)
    }

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

    func testOverlayStaysOpaqueForTheWholeGlideAndFadesOnlyAfterItLands() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])

        let started = Date()
        var finishedAfter: TimeInterval = 0
        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: 0.3) {
            finishedAfter = Date().timeIntervalSince(started)
            completed.fulfill()
        }

        RunLoop.current.run(until: started.addingTimeInterval(0.2))
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.alphaValue, 1, "nothing fades while the ghost is still gliding")

        wait(for: [completed], timeout: 2)
        XCTAssertGreaterThanOrEqual(finishedAfter, 0.3 + WindowAnimationGeometry.finalFadeDuration * 0.9)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.alphaValue, 1)
    }

    func testCrossfadeStacksFreshContentOverAGlidingGhostOnce() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))
        XCTAssertEqual(overlay.settledGhostCount, 0, "a ghost that is not gliding has nothing to cross-fade into")

        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: 0.2) {
            completed.fulfill()
        }
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))
        overlay.crossfade(ghost: 5, to: makeTestImage(width: 8, height: 8))
        XCTAssertEqual(overlay.settledGhostCount, 1)
        XCTAssertEqual(overlay.ghostCount, 1)

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(overlay.settledGhostCount, 0)
    }

    func testTheOverlayWaitsForACrossfadeThatOutlastsTheGlide() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])

        // On a glide this short the minimum cross-fade length carries the cross-fade past the glide's end.
        let duration = 0.08
        let crossfade = WindowAnimationGeometry.crossfadeTiming(elapsed: 0, duration: duration)
        let crossfadeEnd = crossfade.delay + crossfade.length
        XCTAssertGreaterThan(crossfadeEnd, duration)

        let started = Date()
        var finishedAfter: TimeInterval = 0
        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: duration) {
            finishedAfter = Date().timeIntervalSince(started)
            completed.fulfill()
        }
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))

        wait(for: [completed], timeout: 2)
        XCTAssertGreaterThanOrEqual(finishedAfter, crossfadeEnd + WindowAnimationGeometry.finalFadeDuration * 0.9,
                                    "the final fade must not start before the cross-fade has finished")
    }

    func testLayersRestAtTheGlideStartSoAFrameDrawnWithoutTheAnimationCannotJumpAhead() {
        let overlay = GhostOverlayWindow()
        let start = CGRect(x: 0, y: 0, width: 40, height: 40)
        let end = CGRect(x: 50, y: 50, width: 80, height: 80)
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil,
                        ghosts: [GhostSpec(id: 1, image: makeTestImage(), startFrame: start)])
        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: end], removing: [], duration: 0.3) { completed.fulfill() }
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))

        let ghost = try? XCTUnwrap(overlay.ghostLayer(1))
        let settled = try? XCTUnwrap(overlay.settledLayer(1))
        XCTAssertEqual(ghost?.frame, start, "the ghost's resting frame stays at the start")
        XCTAssertEqual(settled?.frame, start, "so does the fresh-content layer's")
        XCTAssertEqual(settled?.opacity, 0, "and that layer rests invisible until its fade shows it")
        for layer in [ghost, settled].compactMap({ $0 }) {
            for key in ["glide-bounds", "glide-position"] {
                let glide = layer.animation(forKey: key)
                XCTAssertEqual(glide?.fillMode, .both, key)
                XCTAssertEqual(glide?.isRemovedOnCompletion, false, "\(key) holds the end state after landing")
            }
        }
        XCTAssertEqual(settled?.animation(forKey: "crossfade")?.isRemovedOnCompletion, false)
        wait(for: [completed], timeout: 2)
    }

    func testCrossfadeIsIgnoredOnceTheOverlayIsFadingAway() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])
        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: 0.1) {
            completed.fulfill()
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.13))
        overlay.crossfade(ghost: 1, to: makeTestImage(width: 8, height: 8))
        XCTAssertEqual(overlay.settledGhostCount, 0)
        wait(for: [completed], timeout: 2)
    }

    func testDismissDuringTheFinalFadeCancelsItAndResetsAlpha() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [ghost])

        let completed = expectation(description: "animation completed")
        completed.isInverted = true
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [], duration: 0.2) {
            completed.fulfill()
        }

        // Interrupt the final fade itself, so dismiss() races a genuinely in-flight animator-driven fade
        // rather than one the generation guard would skip before it started.
        let giveUp = Date().addingTimeInterval(1)
        while overlay.alphaValue >= 1, Date() < giveUp {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertLessThan(overlay.alphaValue, 1, "the final fade is in flight")
        overlay.dismiss()

        wait(for: [completed], timeout: 0.3)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
        XCTAssertEqual(overlay.alphaValue, 1)
    }
}

final class FakeWindow: WindowFrameSource {
    var id: CGWindowID?
    var frame: CGRect

    init(id: CGWindowID?, frame: CGRect) {
        self.id = id
        self.frame = frame
    }

    func animationWindowId() -> CGWindowID? { id }
}

final class FakeSnapshots: WindowSnapshotProvider {
    var failingWindowIds: Set<CGWindowID> = []
    var failBackdrop = false
    var windowCaptures: [CGWindowID] = []
    var backdropCaptures: [(rect: CGRect, excluding: Set<CGWindowID>)] = []
    /// Pixel size of the next image of a window; lets tests play an app that has or has not redrawn yet.
    var windowImageSize: (CGWindowID) -> (width: Int, height: Int) = { _ in (4, 4) }

    func windowImage(windowId: CGWindowID) -> CGImage? {
        windowCaptures.append(windowId)
        guard !failingWindowIds.contains(windowId) else { return nil }
        let size = windowImageSize(windowId)
        return makeTestImage(width: size.width, height: size.height)
    }

    func backdropImage(rect: CGRect, excluding: Set<CGWindowID>) -> CGImage? {
        backdropCaptures.append((rect, excluding))
        return failBackdrop ? nil : makeTestImage()
    }
}

final class FakePresenter: GhostOverlayPresenting {
    let overlayWindowId: CGWindowID = 999
    var presentations: [(frame: CGRect, ghosts: [GhostSpec])] = []
    var backdropUpdates = 0
    var addedGhosts: [GhostSpec] = []
    var animations: [(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double)] = []
    var dismissCount = 0
    var crossfades: [(id: CGWindowID, width: Int)] = []
    /// When false, `animate` keeps its completion instead of calling it, like the real overlay mid-glide.
    var completesImmediately = true
    var pendingCompletion: (() -> Void)?

    func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec]) {
        presentations.append((overlayFrame, ghosts))
    }

    func updateBackdrop(_ image: CGImage?) { backdropUpdates += 1 }
    func addGhost(_ ghost: GhostSpec) { addedGhosts.append(ghost) }

    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void) {
        animations.append((endFrames, removing, duration))
        if completesImmediately { completion() } else { pendingCompletion = completion }
    }

    func crossfade(ghost id: CGWindowID, to image: CGImage) { crossfades.append((id, image.width)) }
    func dismiss() { dismissCount += 1 }
}

final class WindowAnimatorTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let a = CGRect(x: 10, y: 10, width: 300, height: 200)
    private let b = CGRect(x: 500, y: 10, width: 300, height: 200)

    private func makeAnimator(enabled: Bool = true, permission: Bool = true, reduceMotion: Bool = false,
                              duration: Double = 0.22) -> (WindowAnimator, FakeSnapshots, FakePresenter) {
        let snapshots = FakeSnapshots()
        let presenter = FakePresenter()
        let settings = WindowAnimationSettings(isEnabled: { enabled },
                                               hasPermission: { permission },
                                               reduceMotion: { reduceMotion },
                                               duration: { duration },
                                               screenFrames: { [self.screen] })
        let animator = WindowAnimator(snapshots: snapshots, presenterFactory: { presenter }, settings: settings)
        return (animator, snapshots, presenter)
    }

    func testBeginDoesNothingWhenAnimationIsNotAllowed() {
        for (animator, _, presenter) in [makeAnimator(enabled: false), makeAnimator(permission: false), makeAnimator(reduceMotion: true)] {
            XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))
            XCTAssertTrue(presenter.presentations.isEmpty)
        }
    }

    func testBeginCapturesEveryWindowAndPresentsTheOverlayOverTheirScreen() {
        let (animator, snapshots, presenter) = makeAnimator()

        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a), FakeWindow(id: 2, frame: b)], covering: [a])

        XCTAssertNotNil(transaction)
        XCTAssertEqual(transaction?.windowIds, [1, 2])
        XCTAssertEqual(snapshots.windowCaptures, [1, 2])
        XCTAssertEqual(snapshots.backdropCaptures.count, 1)
        XCTAssertEqual(snapshots.backdropCaptures[0].excluding, [1, 2, 999])
        XCTAssertEqual(snapshots.backdropCaptures[0].rect, screen.screenFlipped)
        XCTAssertEqual(presenter.presentations.count, 1)
        XCTAssertEqual(presenter.presentations[0].frame, screen)
        XCTAssertEqual(presenter.presentations[0].ghosts.map(\.id), [1, 2])
    }

    func testWindowsThatCannotBeCapturedAreLeftOut() {
        let (animator, snapshots, presenter) = makeAnimator()
        snapshots.failingWindowIds = [3]
        let derived = AccessibilityElement.deriveWindowId(fromElementHash: 5)

        let transaction = animator.begin(windows: [FakeWindow(id: nil, frame: a),
                                                   FakeWindow(id: derived, frame: a),
                                                   FakeWindow(id: 3, frame: a),
                                                   FakeWindow(id: 4, frame: .null),
                                                   FakeWindow(id: 5, frame: b)],
                                         covering: [a])

        XCTAssertEqual(transaction?.windowIds, [5])
        XCTAssertEqual(presenter.presentations[0].ghosts.map(\.id), [5])
    }

    func testBeginIsAbortedWhenNothingOrNoBackdropCanBeCaptured() {
        let (animator, snapshots, presenter) = makeAnimator()
        snapshots.failingWindowIds = [1]
        XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))

        snapshots.failingWindowIds = []
        snapshots.failBackdrop = true
        XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))

        XCTAssertTrue(presenter.presentations.isEmpty)
    }

    func testEndAnimatesOnlyTheWindowsThatMoved() {
        let (animator, _, presenter) = makeAnimator()
        let moving = FakeWindow(id: 1, frame: a)
        let still = FakeWindow(id: 2, frame: b)
        let transaction = animator.begin(windows: [moving, still], covering: [a])!

        moving.frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        transaction.end()

        XCTAssertEqual(presenter.animations.count, 1)
        XCTAssertEqual(Array(presenter.animations[0].endFrames.keys), [1])
        XCTAssertEqual(presenter.animations[0].endFrames[1],
                       WindowAnimationGeometry.ghostFrame(moving.frame.screenFlipped, inOverlay: screen))
        // The ghost of the window that did not move stays: the backdrop has a hole where it sits, so
        // removing it would make the window disappear for the length of the animation.
        XCTAssertEqual(presenter.animations[0].removing, [])
        XCTAssertEqual(presenter.animations[0].duration, 0.22, accuracy: 0.0001)
        XCTAssertTrue(transaction.isFinished)
    }

    func testEndWithoutAnyMovementJustHidesTheOverlay() {
        let (animator, _, presenter) = makeAnimator()
        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a])!

        transaction.end()

        XCTAssertTrue(presenter.animations.isEmpty)
        XCTAssertEqual(presenter.dismissCount, 1)
    }

    func testEndIsIdempotent() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!
        window.frame = b

        transaction.end()
        transaction.end()

        XCTAssertEqual(presenter.animations.count, 1)
    }

    func testANewTransactionCancelsTheRunningOne() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let first = animator.begin(windows: [window], covering: [a])!

        let second = animator.begin(windows: [window], covering: [a])
        window.frame = b
        first.end()

        XCTAssertNotNil(second)
        XCTAssertTrue(first.isFinished)
        XCTAssertEqual(presenter.dismissCount, 1)
        XCTAssertTrue(presenter.animations.isEmpty, "a cancelled transaction must not animate")
        XCTAssertEqual(presenter.presentations.count, 2)
    }

    func testIncludeAddsAGhostAndRefreshesTheBackdrop() {
        let (animator, snapshots, presenter) = makeAnimator()
        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a])!

        animator.include(FakeWindow(id: 2, frame: b))
        animator.include(FakeWindow(id: 2, frame: b))

        XCTAssertEqual(transaction.windowIds, [1, 2])
        XCTAssertEqual(presenter.addedGhosts.map(\.id), [2])
        XCTAssertEqual(snapshots.backdropCaptures.count, 2)
        XCTAssertEqual(snapshots.backdropCaptures[1].excluding, [1, 2, 999])
        XCTAssertEqual(presenter.backdropUpdates, 1)

        transaction.end()
        animator.include(FakeWindow(id: 3, frame: b))
        XCTAssertEqual(transaction.windowIds, [1, 2], "include after end is ignored")
    }

    func testCancelPendingDismissesAnUnfinishedTransactionOnly() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)

        let pending = animator.begin(windows: [window], covering: [a])!
        animator.cancelPending()

        XCTAssertEqual(presenter.dismissCount, 1)
        XCTAssertTrue(pending.isFinished)

        let second = animator.begin(windows: [window], covering: [a])!
        window.frame = b
        second.end()
        animator.cancelPending()

        XCTAssertEqual(presenter.dismissCount, 1, "a transaction that already ended keeps animating")
        XCTAssertEqual(presenter.animations.count, 1)
    }

    func testCancelCurrentDismissesEvenAfterEnd() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = b
        transaction.end()
        animator.cancelCurrent()

        XCTAssertEqual(presenter.dismissCount, 1)
    }

    func testScreenChangeTearsDownTheOverlay() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = b
        transaction.end()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // The animator only observes for as long as it is alive, so keep it past the notification.
        withExtendedLifetime(animator) {
            XCTAssertEqual(presenter.dismissCount, 1)
        }
    }

    func testAnimationCompletionReleasesTheTransaction() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!
        XCTAssertTrue(animator.hasCurrentTransaction)

        window.frame = b
        // The fake presenter completes synchronously, so the transaction is released by the time end returns.
        transaction.end()
        XCTAssertFalse(animator.hasCurrentTransaction)

        animator.cancelPending()
        XCTAssertEqual(presenter.dismissCount, 0)
    }

    func testBatchIncludeRecapturesTheBackdropOnce() {
        let (animator, snapshots, presenter) = makeAnimator()
        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a])!

        animator.include([FakeWindow(id: 2, frame: b), FakeWindow(id: 3, frame: b)])

        XCTAssertEqual(transaction.windowIds, [1, 2, 3])
        XCTAssertEqual(presenter.addedGhosts.map(\.id), [2, 3])
        XCTAssertEqual(snapshots.backdropCaptures.count, 2)
        XCTAssertEqual(snapshots.backdropCaptures[1].excluding, [1, 2, 3, 999])
        XCTAssertEqual(presenter.backdropUpdates, 1)
    }

    func testAResizedWindowCrossfadesToItsRedrawnContent() {
        let (animator, snapshots, presenter) = makeAnimator(duration: 1)
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        snapshots.windowImageSize = { _ in (800, 600) }
        transaction.end()
        XCTAssertTrue(presenter.crossfades.isEmpty, "the capture waits a couple of frames for the app to redraw")

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(presenter.crossfades.map(\.id), [1])
        XCTAssertEqual(presenter.crossfades.first?.width, 800)
    }

    func testStaleCapturesAreRetriedUntilTheAppHasRedrawn() {
        let (animator, snapshots, presenter) = makeAnimator(duration: 1)
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        var postMoveCaptures = 0
        snapshots.windowImageSize = { _ in
            postMoveCaptures += 1
            return postMoveCaptures <= 2 ? (600, 400) : (800, 600)   // the old 300x200 backing store, twice
        }
        transaction.end()

        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(presenter.crossfades.map(\.id), [1])
        XCTAssertEqual(postMoveCaptures, 3, "it stops as soon as a capture shows the new size")
    }

    func testAWindowThatOnlyMovedIsNotCapturedAgain() {
        let (animator, snapshots, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = b
        transaction.end()

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(snapshots.windowCaptures, [1])
        XCTAssertTrue(presenter.crossfades.isEmpty)
    }

    func testAnAppThatNeverRedrawsKeepsItsSnapshotAndCapturingStops() {
        let (animator, snapshots, presenter) = makeAnimator(duration: 0.2)
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!

        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        transaction.end()

        RunLoop.current.run(until: Date().addingTimeInterval(0.2 * WindowAnimationGeometry.settledCaptureDeadlineFraction + 0.15))
        let capturesAtDeadline = snapshots.windowCaptures.count
        XCTAssertGreaterThan(capturesAtDeadline, 2, "it kept retrying until the deadline")
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(snapshots.windowCaptures.count, capturesAtDeadline, "and then gave up")
        XCTAssertTrue(presenter.crossfades.isEmpty)
    }

    func testASupersededTransactionStopsCapturing() {
        let (animator, snapshots, presenter) = makeAnimator()
        presenter.completesImmediately = false
        let window = FakeWindow(id: 1, frame: a)
        let first = animator.begin(windows: [window], covering: [a])!

        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        snapshots.windowImageSize = { _ in (800, 600) }
        first.end()
        _ = animator.begin(windows: [window], covering: [a])

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(first.isCancelled)
        XCTAssertTrue(presenter.crossfades.isEmpty, "the old glide's content must not land on the new one")
    }

    func testPerformWrapsTheBodyInATransaction() {
        let (animator, _, presenter) = makeAnimator(duration: 5)
        let window = FakeWindow(id: 1, frame: a)

        animator.perform(windows: [window], covering: [a]) {
            window.frame = b
        }

        XCTAssertEqual(presenter.animations.count, 1)
        XCTAssertEqual(presenter.animations[0].duration, WindowAnimationGeometry.maximumDuration)
    }
}
