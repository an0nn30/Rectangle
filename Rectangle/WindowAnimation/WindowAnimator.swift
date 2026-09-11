/// WindowAnimator.swift

import Cocoa

/// A window whose id and frame the animator can read. Frames are accessibility frames
/// (origin top-left of the main display).
protocol WindowFrameSource: AnyObject {
    func animationWindowId() -> CGWindowID?
    var frame: CGRect { get }
}

extension AccessibilityElement: WindowFrameSource {
    func animationWindowId() -> CGWindowID? {
        getWindowId()
    }
}

/// Everything the animator asks the environment, as closures so tests can substitute answers.
struct WindowAnimationSettings {
    let isEnabled: () -> Bool
    let hasPermission: () -> Bool
    let reduceMotion: () -> Bool
    let duration: () -> Double
    /// AppKit frames of every screen.
    let screenFrames: () -> [CGRect]

    static let live = WindowAnimationSettings(
        isEnabled: { Defaults.windowAnimation.enabled },
        hasPermission: { ScreenRecordingAuthorization.hasAccess },
        reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        duration: { Double(Defaults.windowAnimationDuration.value) },
        screenFrames: { NSScreen.screens.map { $0.frame } }
    )
}

/// One animated move: captured at `begin`, the real windows move underneath the overlay, then `end`
/// glides the ghosts to wherever the windows actually ended up.
final class WindowMoveTransaction {

    private struct Entry {
        let source: WindowFrameSource
        let id: CGWindowID
        let startFrame: CGRect
    }

    private var entries: [Entry] = []
    private var excluded: Set<CGWindowID>
    /// AppKit coordinates.
    private let overlayFrame: CGRect
    private let snapshots: WindowSnapshotProvider
    private let presenter: GhostOverlayPresenting
    private let duration: Double

    private(set) var isFinished = false
    /// Set by `cancel()`, including after `end()`: stops post-move captures, so a transaction superseded by
    /// a newer one can never hand the shared overlay an image meant for its own, already replaced, glide.
    private(set) var isCancelled = false

    /// Called once the transaction is done with the overlay (the animation finished, or there was
    /// nothing to animate). The animator uses it to drop its reference to this transaction.
    var onFinished: (() -> Void)?

    var windowIds: [CGWindowID] {
        entries.map { $0.id }
    }

    /// Nil when nothing could be captured; the caller then moves windows instantly as before.
    fileprivate init?(windows: [WindowFrameSource],
                      overlayFrame: CGRect,
                      snapshots: WindowSnapshotProvider,
                      presenter: GhostOverlayPresenting,
                      duration: Double) {
        self.overlayFrame = overlayFrame
        self.snapshots = snapshots
        self.presenter = presenter
        self.duration = duration
        self.excluded = [presenter.overlayWindowId]

        var ghosts: [GhostSpec] = []
        for window in windows {
            if let (entry, ghost) = capture(window) {
                entries.append(entry)
                excluded.insert(entry.id)
                ghosts.append(ghost)
            }
        }
        guard !entries.isEmpty else {
            Logger.log("Window animation: no window could be captured")
            return nil
        }
        guard let backdrop = captureBackdrop() else {
            return nil
        }
        presenter.present(overlayFrame: overlayFrame, backdrop: backdrop, ghosts: ghosts)
    }

    /// Adds a window that will move later in the same action (e.g. a cooperative resize neighbour).
    /// Must be called before that window moves.
    func include(_ window: WindowFrameSource) {
        include([window])
    }

    /// Batched form of `include(_:)`: every window is captured before the backdrop is taken again, so a
    /// group of neighbours costs one backdrop capture instead of one each. The ghosts are added before the
    /// backdrop is swapped in, so no composited frame can show the backdrop's hole without a ghost over it.
    func include(_ windows: [WindowFrameSource]) {
        guard !isFinished else { return }

        var ghosts: [GhostSpec] = []
        for window in windows {
            if let (entry, ghost) = capture(window) {
                entries.append(entry)
                excluded.insert(entry.id)
                ghosts.append(ghost)
            }
        }
        guard !ghosts.isEmpty else { return }

        ghosts.forEach(presenter.addGhost)
        if let backdrop = captureBackdrop() {
            presenter.updateBackdrop(backdrop)
        }
    }

    /// Reads the windows' final frames and starts the animation. Safe to call more than once.
    func end() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.end() }
            return
        }
        guard !isFinished else { return }
        isFinished = true

        let start = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.startFrame) })
        let final = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.source.frame) })
        let moved = WindowAnimationGeometry.movedWindowIds(start: start, final: final)
        guard !moved.isEmpty else {
            presenter.dismiss()
            onFinished?()
            return
        }

        let endFrames = Dictionary(uniqueKeysWithValues: moved.map { id -> (CGWindowID, CGRect) in
            (id, WindowAnimationGeometry.ghostFrame(final[id]!.screenFlipped, inOverlay: overlayFrame))
        })
        // Nothing is removed: the backdrop has a hole wherever a captured window sits, so dropping the ghost
        // of a window that did not move would make that window vanish for the length of the animation. Its
        // ghost is pixel-identical to the real window underneath, so the overlay's exit reveals it unchanged.
        let finished = onFinished
        presenter.animate(endFrames: endFrames, removing: [], duration: duration, completion: { finished?() })

        // A resized window's ghost is a stretched snapshot of its old layout. Capture its redrawn content and
        // cross-fade to it mid-glide. A window that only moved needs nothing: its snapshot is still accurate.
        let resized = moved.reduce(into: [CGWindowID: CGSize]()) { result, id in
            if start[id]!.size != final[id]!.size { result[id] = final[id]!.size }
        }
        if !resized.isEmpty {
            captureSettledContent(resized,
                                  startedAt: CFAbsoluteTimeGetCurrent(),
                                  after: WindowAnimationGeometry.settledCaptureDelay)
        }
    }

    /// Drops the overlay without animating if the animation has not started. Used when a newer transaction
    /// supersedes this one; after `end()` it only stops this transaction's pending captures.
    func cancel() {
        isCancelled = true
        guard !isFinished else { return }
        isFinished = true
        presenter.dismiss()
    }

    /// Captures each window in `pending` (id to its new size in points) once the app has redrawn it at that
    /// size, and hands the image to the overlay. Retries once per frame until partway through the glide;
    /// a window never caught just keeps its stretched snapshot.
    private func captureSettledContent(_ pending: [CGWindowID: CGSize], startedAt: CFAbsoluteTime, after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isCancelled else { return }
            var remaining = pending
            for (id, size) in pending {
                guard let image = self.snapshots.windowImage(windowId: id),
                      WindowAnimationGeometry.isSettledCapture(imageSize: CGSize(width: image.width, height: image.height),
                                                               frameSize: size)
                else { continue }
                self.presenter.crossfade(ghost: id, to: image)
                remaining[id] = nil
            }
            guard !remaining.isEmpty else { return }

            let retry = WindowAnimationGeometry.settledCaptureRetryInterval
            let deadline = self.duration * WindowAnimationGeometry.settledCaptureDeadlineFraction
            if CFAbsoluteTimeGetCurrent() - startedAt + retry <= deadline {
                self.captureSettledContent(remaining, startedAt: startedAt, after: retry)
            } else {
                Logger.log("Window animation: no redrawn content for \(remaining.keys.sorted()) in time; keeping the stretched snapshot")
            }
        }
    }

    /// Captures the backdrop for the current exclusion set, logging how long the window server took:
    /// this is the one blocking step between the user's keypress and the overlay appearing.
    private func captureBackdrop() -> CGImage? {
        let started = CFAbsoluteTimeGetCurrent()
        let image = snapshots.backdropImage(rect: overlayFrame.screenFlipped, excluding: excluded)
        if Logger.logging {
            let ms = Int(((CFAbsoluteTimeGetCurrent() - started) * 1000).rounded())
            Logger.log("Window animation: backdrop capture took \(ms) ms")
        }
        return image
    }

    private func capture(_ window: WindowFrameSource) -> (Entry, GhostSpec)? {
        guard let id = window.animationWindowId(),
              WindowAnimationGeometry.isCapturable(windowId: id),
              !entries.contains(where: { $0.id == id })
        else { return nil }
        let frame = window.frame
        guard !frame.isNull, let image = snapshots.windowImage(windowId: id) else { return nil }
        let ghost = GhostSpec(id: id,
                              image: image,
                              startFrame: WindowAnimationGeometry.ghostFrame(frame.screenFlipped, inOverlay: overlayFrame))
        return (Entry(source: window, id: id, startFrame: frame), ghost)
    }
}

/// Entry point for animated moves. Wrap the code that moves windows in `begin` / `end` (or `perform`).
final class WindowAnimator {

    static let shared = WindowAnimator()

    private let snapshots: WindowSnapshotProvider
    private let presenterFactory: () -> GhostOverlayPresenting
    private let settings: WindowAnimationSettings
    private var presenter: GhostOverlayPresenting?
    private var current: WindowMoveTransaction?

    init(snapshots: WindowSnapshotProvider = CGWindowSnapshotProvider(),
         presenterFactory: @escaping () -> GhostOverlayPresenting = { GhostOverlayWindow() },
         settings: WindowAnimationSettings = .live) {
        self.snapshots = snapshots
        self.presenterFactory = presenterFactory
        self.settings = settings
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    /// Starts an animated move of `windows`. `rects` (AppKit coordinates) are where the windows are and
    /// where they are expected to go; the overlay covers every screen they touch. Returns nil, and shows
    /// nothing, when animation is off or impossible, in which case the move simply happens instantly.
    func begin(windows: [WindowFrameSource], covering rects: [CGRect]) -> WindowMoveTransaction? {
        guard WindowAnimationGeometry.shouldAnimate(enabled: settings.isEnabled(),
                                                    hasPermission: settings.hasPermission(),
                                                    reduceMotion: settings.reduceMotion())
        else { return nil }

        current?.cancel()
        current = nil

        let overlayFrame = WindowAnimationGeometry.overlayRect(screenFrames: settings.screenFrames(), touching: rects)
        guard !overlayFrame.isNull, !overlayFrame.isEmpty else { return nil }

        let presenter = self.presenter ?? presenterFactory()
        self.presenter = presenter

        let transaction = WindowMoveTransaction(windows: windows,
                                                overlayFrame: overlayFrame,
                                                snapshots: snapshots,
                                                presenter: presenter,
                                                duration: WindowAnimationGeometry.clampedDuration(settings.duration()))
        transaction?.onFinished = { [weak self, weak transaction] in
            guard let self, let transaction, self.current === transaction else { return }
            self.current = nil
        }
        current = transaction
        return transaction
    }

    /// True while a transaction owns the overlay. Exposed for tests.
    var hasCurrentTransaction: Bool {
        current != nil
    }

    /// Adds a window to the transaction in progress, if any. Call before that window moves.
    func include(_ window: WindowFrameSource) {
        current?.include(window)
    }

    /// Adds several windows to the transaction in progress, if any, with a single backdrop recapture.
    /// Call before those windows move.
    func include(_ windows: [WindowFrameSource]) {
        current?.include(windows)
    }

    func perform(windows: [WindowFrameSource], covering rects: [CGRect], _ body: () -> Void) {
        let transaction = begin(windows: windows, covering: rects)
        body()
        transaction?.end()
    }

    /// Tears the overlay down now, whatever state it is in: a transaction that has not ended yet is
    /// cancelled, and an animation already in flight is cut short rather than left over a changed display.
    func cancelCurrent() {
        current?.cancel()
        current = nil
        presenter?.dismiss()
    }

    /// Drops an overlay that was presented but never ended, which happens when a newer action supersedes
    /// an execution before it reaches its own `begin`. A transaction that has already ended is left alone
    /// so a running animation plays out.
    func cancelPending() {
        guard let current, !current.isFinished else { return }
        current.cancel()
        self.current = nil
    }

    @objc private func screensChanged() {
        cancelCurrent()
    }
}
