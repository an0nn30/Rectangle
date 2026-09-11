/// GhostOverlayWindow.swift

import Cocoa

/// A captured window to draw on the overlay. `startFrame` is in the overlay's local AppKit coordinates.
struct GhostSpec {
    let id: CGWindowID
    let image: CGImage
    let startFrame: CGRect
}

/// What the animator needs from the overlay. `GhostOverlayWindow` is the real thing; tests use a fake.
protocol GhostOverlayPresenting: AnyObject {
    /// The overlay's own window id, so backdrop captures can leave it out.
    var overlayWindowId: CGWindowID { get }
    /// Shows the overlay at `overlayFrame` (AppKit coordinates) with the backdrop and ghosts, ordered front
    /// and committed to the window server before returning, so the real windows can move underneath unseen.
    func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec])
    func updateBackdrop(_ image: CGImage?)
    func addGhost(_ ghost: GhostSpec)
    /// Glides the ghosts in `endFrames` to their new frames and removes the ghosts in `removing`. The overlay
    /// stays fully opaque for the whole glide and is hidden the moment it lands, then `completion` is called.
    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void)
    /// Hides the overlay immediately, cancelling any running animation. Its completion is not called.
    func dismiss()
}

final class GhostOverlayWindow: NSPanel, GhostOverlayPresenting {

    private let backdropLayer = CALayer()
    private var ghostLayers: [CGWindowID: CALayer] = [:]
    /// Scale the captures are drawn at. The overlay spans every screen the move touches, so a ghost can
    /// cross from a Retina display onto a non-Retina one: the highest scale in use keeps it sharp there
    /// and merely downsamples elsewhere.
    private var captureScale: CGFloat = 1
    /// Bumped whenever the overlay's content is replaced or hidden, so stale animation callbacks are ignored.
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let content = NSView()
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        backdropLayer.contentsGravity = .resize
        content.layer?.addSublayer(backdropLayer)
        contentView = content
    }

    var overlayWindowId: CGWindowID {
        CGWindowID(max(windowNumber, 0))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var ghostCount: Int {
        ghostLayers.count
    }

    func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec]) {
        generation += 1
        clearGhosts()
        setFrame(overlayFrame, display: false)
        captureScale = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? backingScaleFactor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.frame = CGRect(origin: .zero, size: overlayFrame.size)
        backdropLayer.contentsScale = captureScale
        backdropLayer.contents = backdrop
        ghosts.forEach(addGhostLayer)
        CATransaction.commit()

        orderFrontRegardless()
        displayIfNeeded()
        CATransaction.flush()
    }

    func updateBackdrop(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.contents = image
        CATransaction.commit()
    }

    func addGhost(_ ghost: GhostSpec) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addGhostLayer(ghost)
        CATransaction.commit()
    }

    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void) {
        generation += 1
        let thisGeneration = generation

        removing.forEach { ghostLayers.removeValue(forKey: $0)?.removeFromSuperlayer() }

        // Standalone layers animate bounds and position implicitly with the transaction's timing. The
        // completion block runs once the glide has landed; the overlay is then cut away with no fade, revealing
        // the real windows, which already sit at exactly those frames.
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.1, 0.9, 0.2, 1))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == thisGeneration else { return }
            self.dismiss()
            completion()
        }
        for (id, end) in endFrames {
            guard let layer = ghostLayers[id] else { continue }
            layer.bounds = CGRect(origin: .zero, size: end.size)
            layer.position = CGPoint(x: end.midX, y: end.midY)
        }
        CATransaction.commit()
    }

    func dismiss() {
        generation += 1
        orderOut(nil)
        clearGhosts()
        backdropLayer.contents = nil
    }

    private func addGhostLayer(_ ghost: GhostSpec) {
        let layer = CALayer()
        layer.contents = ghost.image
        layer.contentsGravity = .resize
        layer.contentsScale = captureScale
        layer.frame = ghost.startFrame
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: -8)
        contentView?.layer?.addSublayer(layer)
        ghostLayers[ghost.id] = layer
    }

    private func clearGhosts() {
        ghostLayers.values.forEach { $0.removeFromSuperlayer() }
        ghostLayers.removeAll()
    }
}
