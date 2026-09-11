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
    /// Glides the ghosts in `endFrames` to their new frames and removes the ghosts in `removing`. Once the
    /// glide has landed, and any cross-fade started by `crossfade(ghost:to:)` has finished, the overlay fades
    /// out briefly, hides, and `completion` is called.
    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void)
    /// Cross-fades a gliding ghost to `image`, the window's content captured after it moved, following the
    /// same glide. Ignored for a ghost that is not gliding, or once the overlay has started fading away.
    func crossfade(ghost id: CGWindowID, to image: CGImage)
    /// Hides the overlay immediately, cancelling any running animation. Its completion is not called.
    func dismiss()
}

final class GhostOverlayWindow: NSPanel, GhostOverlayPresenting {

    /// Where a ghost glides from and to, in overlay coordinates, so a cross-fade layer added mid-flight can
    /// follow exactly the same path.
    private struct Glide {
        let from: CGRect
        let to: CGRect
    }

    private let backdropLayer = CALayer()
    private var ghostLayers: [CGWindowID: CALayer] = [:]
    /// The fresh-content layers stacked over their ghosts during a cross-fade.
    private var settledLayers: [CGWindowID: CALayer] = [:]
    private var glides: [CGWindowID: Glide] = [:]
    /// Media time at which the current glide started, and how long it lasts.
    private var glideStart: CFTimeInterval = 0
    private var glideDuration: Double = 0
    /// Media time at which the last cross-fade scheduled so far ends.
    private var crossfadeEnd: CFTimeInterval = 0
    /// Set once the final fade has begun; later cross-fades are ignored.
    private var isFinishing = false
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

    /// Number of ghosts currently cross-fading (or cross-faded) to fresh content. Exposed for tests.
    var settledGhostCount: Int {
        settledLayers.count
    }

    func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec]) {
        generation += 1
        clearGhosts()
        setFrame(overlayFrame, display: false)
        resetAlpha()
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

        glideStart = CACurrentMediaTime()
        glideDuration = duration
        crossfadeEnd = 0
        isFinishing = false
        glides.removeAll()
        for (id, end) in endFrames {
            guard let layer = ghostLayers[id] else { continue }
            let glide = Glide(from: layer.frame, to: end)
            glides[id] = glide
            apply(glide, to: layer)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.finishWhenSettled(generation: thisGeneration, completion: completion)
        }
    }

    func crossfade(ghost id: CGWindowID, to image: CGImage) {
        guard !isFinishing, settledLayers[id] == nil,
              let ghostLayer = ghostLayers[id], let glide = glides[id]
        else { return }

        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = captureScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = glide.from
        contentView?.layer?.insertSublayer(layer, above: ghostLayer)
        CATransaction.commit()
        settledLayers[id] = layer
        apply(glide, to: layer)

        let now = CACurrentMediaTime()
        let timing = WindowAnimationGeometry.crossfadeTiming(elapsed: now - glideStart, duration: glideDuration)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = layer.convertTime(now + timing.delay, from: nil)
        fade.duration = timing.length
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "crossfade")
        crossfadeEnd = max(crossfadeEnd, now + timing.delay + timing.length)
    }

    func dismiss() {
        generation += 1
        orderOut(nil)
        resetAlpha()
        clearGhosts()
        backdropLayer.contents = nil
    }

    /// Moves `layer` along `glide` with the glide's timing curve. The animation is anchored at the glide's
    /// start time, so a layer added mid-flight lands at exactly the same point as the ghost it covers.
    private func apply(_ glide: Glide, to layer: CALayer) {
        let fromBounds = CGRect(origin: .zero, size: glide.from.size)
        let toBounds = CGRect(origin: .zero, size: glide.to.size)
        let fromPosition = CGPoint(x: glide.from.midX, y: glide.from.midY)
        let toPosition = CGPoint(x: glide.to.midX, y: glide.to.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = toBounds
        layer.position = toPosition
        CATransaction.commit()

        let (x1, y1, x2, y2) = WindowAnimationGeometry.glideTimingControlPoints
        let timing = CAMediaTimingFunction(controlPoints: x1, y1, x2, y2)
        let begin = layer.convertTime(glideStart, from: nil)
        for (keyPath, from, to) in [("bounds", NSValue(rect: fromBounds), NSValue(rect: toBounds)),
                                    ("position", NSValue(point: fromPosition), NSValue(point: toPosition))] {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.beginTime = begin
            animation.duration = glideDuration
            animation.fillMode = .backwards
            animation.timingFunction = timing
            layer.add(animation, forKey: "glide-\(keyPath)")
        }
    }

    /// Runs once the glide has landed. Waits for a cross-fade still in progress, then fades the overlay
    /// away and reports completion.
    private func finishWhenSettled(generation expected: Int, completion: @escaping () -> Void) {
        guard generation == expected else { return }
        let remaining = crossfadeEnd - CACurrentMediaTime()
        if remaining > 0.001 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.finishWhenSettled(generation: expected, completion: completion)
            }
            return
        }
        isFinishing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = WindowAnimationGeometry.finalFadeDuration
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == expected else { return }
            self.dismiss()
            completion()
        })
    }

    /// Sets `alphaValue` back to fully opaque, replacing (rather than merely overwriting) any fade
    /// left in flight: a plain assignment can be overwritten by the next tick of an already-running
    /// `animator()`-driven animation, but a zero-duration animation group retargets it.
    private func resetAlpha() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 1
        }
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
        settledLayers.values.forEach { $0.removeFromSuperlayer() }
        settledLayers.removeAll()
        glides.removeAll()
        isFinishing = false
    }
}
