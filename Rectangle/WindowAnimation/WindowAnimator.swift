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
        guard let backdrop = snapshots.backdropImage(rect: overlayFrame.screenFlipped, excluding: excluded) else {
            return nil
        }
        presenter.present(overlayFrame: overlayFrame, backdrop: backdrop, ghosts: ghosts)
    }

    /// Adds a window that will move later in the same action (e.g. a cooperative resize neighbour).
    /// Must be called before that window moves.
    func include(_ window: WindowFrameSource) {
        guard !isFinished, let (entry, ghost) = capture(window) else { return }
        entries.append(entry)
        excluded.insert(entry.id)
        if let backdrop = snapshots.backdropImage(rect: overlayFrame.screenFlipped, excluding: excluded) {
            presenter.updateBackdrop(backdrop)
        }
        presenter.addGhost(ghost)
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
            return
        }

        let endFrames = Dictionary(uniqueKeysWithValues: moved.map { id -> (CGWindowID, CGRect) in
            (id, WindowAnimationGeometry.ghostFrame(final[id]!.screenFlipped, inOverlay: overlayFrame))
        })
        let removing = Set(start.keys).subtracting(moved)
        presenter.animate(endFrames: endFrames, removing: removing, duration: duration, completion: {})
    }

    /// Drops the overlay without animating. Used when a newer transaction supersedes this one.
    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        presenter.dismiss()
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
        current = transaction
        return transaction
    }

    /// Adds a window to the transaction in progress, if any. Call before that window moves.
    func include(_ window: WindowFrameSource) {
        current?.include(window)
    }

    func perform(windows: [WindowFrameSource], covering rects: [CGRect], _ body: () -> Void) {
        let transaction = begin(windows: windows, covering: rects)
        body()
        transaction?.end()
    }

    func cancelCurrent() {
        current?.cancel()
        current = nil
    }

    @objc private func screensChanged() {
        cancelCurrent()
    }
}
