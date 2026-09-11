/// WindowAnimationGeometry.swift

import Foundation

/// Pure policy and geometry for the window move animation. No AppKit windows, no accessibility calls.
/// Rects are in AppKit coordinates (origin at the bottom-left of the main screen) unless stated otherwise.
enum WindowAnimationGeometry {

    static let minimumDuration: Double = 0.05
    static let maximumDuration: Double = 1.0

    /// Control points of the glide's cubic Bézier timing curve. Fitted to a screen recording of Windows 11
    /// maximizing and restoring an Explorer window (within 1% of every frame of both): a gentle start, a very
    /// fast middle, and a settling finish.
    static let glideTimingControlPoints: (Float, Float, Float, Float) = (0.85, 0.05, 0.05, 0.9)

    /// When, as fractions of the glide, the ghost cross-fades from its pre-move snapshot to the window's
    /// freshly rendered content. Windows 11 swaps content during the fast middle of the motion, while the eye
    /// is tracking movement, so two layouts are never seen overlapping at rest.
    static let crossfadeStartFraction: Double = 0.28
    static let crossfadeEndFraction: Double = 0.62
    /// Shortest cross-fade, used when the fresh content arrives too late for the planned window.
    static let minimumCrossfadeDuration: Double = 0.08

    /// How long the overlay takes to fade away once the glide has landed. By then the ghost shows the
    /// window's real pixels, so this only softens anything the app redrew after the capture.
    static let finalFadeDuration: Double = 0.08

    /// Timing of the post-move captures: first attempt after two display frames, then once per frame
    /// until this fraction of the glide has passed.
    static let settledCaptureDelay: Double = 0.033
    static let settledCaptureRetryInterval: Double = 0.016
    static let settledCaptureDeadlineFraction: Double = 0.6

    /// Ids Rectangle derives itself when macOS vends none (see `AccessibilityElement.deriveWindowId`)
    /// have this bit set. They are not real window ids and cannot be captured.
    static let derivedWindowIdBit: CGWindowID = 0x8000_0000

    static func shouldAnimate(enabled: Bool, hasPermission: Bool, reduceMotion: Bool) -> Bool {
        enabled && hasPermission && !reduceMotion
    }

    static func clampedDuration(_ requested: Double) -> Double {
        guard requested.isFinite else { return minimumDuration }
        return min(max(requested, minimumDuration), maximumDuration)
    }

    static func isCapturable(windowId: CGWindowID) -> Bool {
        windowId != 0 && windowId & derivedWindowIdBit == 0
    }

    /// The union of the screen frames that any of `rects` intersects. Falls back to every screen
    /// when none is touched, so a window that ends up somewhere unexpected is still covered.
    static func overlayRect(screenFrames: [CGRect], touching rects: [CGRect]) -> CGRect {
        let touched = screenFrames.filter { screen in
            rects.contains { !$0.isNull && screen.intersects($0) }
        }
        let chosen = touched.isEmpty ? screenFrames : touched
        return chosen.reduce(CGRect.null) { $0.union($1) }
    }

    /// Converts an AppKit-space frame into the overlay window's local coordinate space.
    static func ghostFrame(_ frame: CGRect, inOverlay overlayRect: CGRect) -> CGRect {
        frame.offsetBy(dx: -overlayRect.minX, dy: -overlayRect.minY)
    }

    /// When the cross-fade should start (as a delay from now) and how long it should last, given how far
    /// into the glide the fresh content arrived. Early arrivals wait for the planned window; late ones start
    /// at once and still get the minimum length.
    static func crossfadeTiming(elapsed: Double, duration: Double) -> (delay: Double, length: Double) {
        let start = max(elapsed, crossfadeStartFraction * duration)
        let end = max(start + minimumCrossfadeDuration, crossfadeEndFraction * duration)
        return (start - elapsed, end - start)
    }

    /// Whether a capture taken after the move shows the window at its new size, as opposed to a stale
    /// backing store the app has not redrawn yet. The image must be the frame's size at a whole-number
    /// backing scale (1x, 2x, 3x), give or take two pixels of rounding.
    static func isSettledCapture(imageSize: CGSize, frameSize: CGSize) -> Bool {
        guard frameSize.width >= 1, frameSize.height >= 1 else { return false }
        let scale = (imageSize.width / frameSize.width).rounded()
        guard scale >= 1, scale <= 3 else { return false }
        return abs(imageSize.width - frameSize.width * scale) <= 2
            && abs(imageSize.height - frameSize.height * scale) <= 2
    }

    /// Ids whose frame changed between begin and end, in ascending order so callers are deterministic.
    static func movedWindowIds(start: [CGWindowID: CGRect], final: [CGWindowID: CGRect]) -> [CGWindowID] {
        start.compactMap { id, startFrame -> CGWindowID? in
            guard let endFrame = final[id], !endFrame.isNull, !endFrame.equalTo(startFrame) else { return nil }
            return id
        }.sorted()
    }
}
