/// ScreenRecordingAuthorization.swift

import Cocoa

/// Screen Recording permission, needed to capture other apps' windows for the move animation.
enum ScreenRecordingAuthorization {

    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }
}
