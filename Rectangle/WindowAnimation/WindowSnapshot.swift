/// WindowSnapshot.swift

import Cocoa

/// Captures the images the window move animation is made of.
/// `rect` arguments are in CoreGraphics global coordinates (origin top-left of the main display),
/// the same space as accessibility window frames.
protocol WindowSnapshotProvider {
    /// The window's own pixels, without its shadow. Nil when it cannot be captured.
    func windowImage(windowId: CGWindowID) -> CGImage?
    /// Everything on screen inside `rect` except the windows in `excluding`, desktop included.
    func backdropImage(rect: CGRect, excluding: Set<CGWindowID>) -> CGImage?
}

enum WindowSnapshot {

    /// Ids to composite for a backdrop, front to back, keeping the desktop and dropping `excluding`.
    static func backdropWindowIds(onScreen ids: [CGWindowID], excluding: Set<CGWindowID>) -> [CGWindowID] {
        ids.filter { !excluding.contains($0) }
    }

    /// The window ids of `infos`, in the order the window server listed them, minus everything Rectangle
    /// owns: the overlay itself, and panels such as the drag-to-snap footprint, which the window server
    /// often still reports as on screen when a move begins and which must not be baked into the backdrop.
    static func backdropCandidateIds(from infos: [[String: Any]], ownPid: pid_t) -> [CGWindowID] {
        infos.compactMap { info -> CGWindowID? in
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t(truncating: $0) }
            guard pid != ownPid else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber).map { CGWindowID(truncating: $0) }
        }
    }

    /// Every on-screen window front to back, including the desktop picture, unlike `WindowUtil.getWindowList`.
    static func onScreenWindowIds() -> [CGWindowID] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return backdropCandidateIds(from: infos, ownPid: ProcessInfo.processInfo.processIdentifier)
    }
}

/// CoreGraphics-backed capture. `CGWindowListCreateImage` is deprecated since macOS 14 but still works
/// with the Screen Recording permission, and the 10.15 deployment target rules out ScreenCaptureKit.
struct CGWindowSnapshotProvider: WindowSnapshotProvider {

    func windowImage(windowId: CGWindowID) -> CGImage? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution]),
              image.width > 1, image.height > 1
        else {
            Logger.log("Window animation: could not capture window \(windowId)")
            return nil
        }
        return image
    }

    func backdropImage(rect: CGRect, excluding: Set<CGWindowID>) -> CGImage? {
        let ids = WindowSnapshot.backdropWindowIds(onScreen: WindowSnapshot.onScreenWindowIds(), excluding: excluding)
        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: max(ids.count, 1))
        defer { values.deallocate() }
        for (i, id) in ids.enumerated() {
            values[i] = UnsafeRawPointer(bitPattern: UInt(id))
        }
        guard let array = CFArrayCreate(kCFAllocatorDefault, values, ids.count, nil),
              let image = CGImage(windowListFromArrayScreenBounds: rect, windowArray: array, imageOption: [.bestResolution]),
              image.width > 1, image.height > 1
        else {
            Logger.log("Window animation: could not capture backdrop \(rect.debugDescription)")
            return nil
        }
        return image
    }
}
