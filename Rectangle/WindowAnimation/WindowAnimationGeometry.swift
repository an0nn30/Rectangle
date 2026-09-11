/// WindowAnimationGeometry.swift

import Foundation

/// Pure policy and geometry for the window move animation. No AppKit windows, no accessibility calls.
/// Rects are in AppKit coordinates (origin at the bottom-left of the main screen) unless stated otherwise.
enum WindowAnimationGeometry {

    static let minimumDuration: Double = 0.05
    static let maximumDuration: Double = 1.0

    /// Fraction of the animation after which the overlay starts fading out, so the stretched
    /// snapshot cross-fades into the freshly rendered real window.
    static let fadeStartFraction: Double = 0.65

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

    /// Ids whose frame changed between begin and end, in ascending order so callers are deterministic.
    static func movedWindowIds(start: [CGWindowID: CGRect], final: [CGWindowID: CGRect]) -> [CGWindowID] {
        start.compactMap { id, startFrame -> CGWindowID? in
            guard let endFrame = final[id], !endFrame.isNull, !endFrame.equalTo(startFrame) else { return nil }
            return id
        }.sorted()
    }
}
