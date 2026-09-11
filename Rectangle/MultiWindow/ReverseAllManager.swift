/// ReverseAllManager.swift

import Cocoa
import MASShortcut

class ReverseAllManager {

    static func reverseAll(windowElement: AccessibilityElement? = nil) {
        let sd = ScreenDetection()

        let currentWindow = windowElement ?? AccessibilityElement.getFrontWindowElement()
        guard let currentScreen = sd.detectScreens(using: currentWindow)?.currentScreen else { return }

        let windows = AccessibilityElement.getAllWindowElements()

        let screenFrame = currentScreen.adjustedVisibleFrame()

        let windowsOnScreen = windows.filter { w in
            if Defaults.todo.userEnabled && TodoManager.isTodoWindow(w) { return false }
            return sd.detectScreens(using: w)?.currentScreen == currentScreen
        }

        WindowAnimator.shared.perform(windows: windowsOnScreen, covering: [currentScreen.frame]) {
            for w in windowsOnScreen {
                reverseWindowPosition(w, screenFrame: screenFrame)
            }
        }
    }

    private static func reverseWindowPosition(_ w: AccessibilityElement, screenFrame: CGRect) {
        var rect = w.frame

        let offsetFromLeft = rect.minX - screenFrame.minX

        rect.origin.x = screenFrame.maxX - offsetFromLeft - rect.width

        w.setFrame(rect)
    }
}
