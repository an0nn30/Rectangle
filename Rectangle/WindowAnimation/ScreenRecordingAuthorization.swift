/// ScreenRecordingAuthorization.swift

import Cocoa

/// Screen Recording permission, needed to capture other apps' windows for the move animation.
enum ScreenRecordingAuthorization {

    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks macOS for access and, if it is still missing, explains what to do.
    /// `CGRequestScreenCaptureAccess` shows the system prompt only once per app; afterwards it just returns false,
    /// so the alert covers both the "just prompted" and the "previously denied" cases.
    /// - Returns: whether access is available right now.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if hasAccess { return true }
        if CGRequestScreenCaptureAccess() { return true }
        showMissingAccessAlert()
        return false
    }

    private static func showMissingAccessAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Screen Recording permission is needed to animate window movement", tableName: "Main", value: "", comment: "")
        alert.informativeText = NSLocalizedString("Rectangle takes a snapshot of a window to animate it. If macOS just asked, choose Allow. Otherwise enable Rectangle under Privacy & Security > Screen Recording. Quit and reopen Rectangle afterwards. Until then, windows move instantly.", tableName: "Main", value: "", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", tableName: "Main", value: "", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", tableName: "Main", value: "", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
