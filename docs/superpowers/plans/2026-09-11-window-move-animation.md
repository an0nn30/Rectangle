# Window Move Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate Rectangle's window moves and resizes Windows 11 style: a snapshot of the window glides and scales from its old frame to its new one while the real window snaps into place underneath.

**Architecture:** A `WindowAnimator` wraps each Rectangle action in a transaction. At begin it captures the moving windows and a backdrop of the screen (via `CGWindowListCreateImage`), shows a full-screen click-through overlay with those images, then the existing move code runs untouched, then at end it animates the ghost layers to the windows' actual final frames and fades the overlay out. Pure geometry and policy live in a separate enum for unit testing; capture and overlay are behind protocols so the animator is testable with fakes.

**Tech Stack:** Swift 5, AppKit (`NSPanel`, Core Animation), CoreGraphics window capture (`CGWindowListCreateImage`, `CGWindowListCreateImageFromArray`, `CGPreflightScreenCaptureAccess`), XCTest via `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-09-11-window-move-animation-design.md`

## Global Constraints

- Deployment target is macOS 10.15; no ScreenCaptureKit, no APIs newer than 10.15 without `#available` guards.
- No private APIs (no SkyLight / `SLS*` / `CGS*` calls).
- The setting is off by default. Defaults keys: `windowAnimation` (bool) and `windowAnimationDuration` (float, default `0.22`).
- Animation duration is clamped to `0.05 … 1.0` seconds; the overlay fade starts at 65% of the duration.
- Animation must be skipped (instant move, exactly today's behaviour) when the setting is off, Screen Recording permission is missing, Reduce Motion is on, any capture fails, or no window frame actually changed.
- Existing move code (`WindowMover` chain, cooperative resize, cross-display retries) stays functionally unchanged; the animator only wraps it.
- Every new source file must be registered in `Rectangle.xcodeproj/project.pbxproj` (this project does not use synchronized folders). Use the helper script from Task 1.
- Localizable UI strings go through `NSLocalizedString(_, tableName: "Main", value: "", comment: "")` like the rest of the settings UI.
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

**Deviation from the spec (decided while planning):** the drag unsnap-restore in `SnappingManager.unsnapRestore` is NOT animated. It runs while the user is still dragging; a full-screen overlay would hide the real window for the animation's duration and the drag would appear to freeze. Windows 11 also resizes the window under the cursor without an animation in that case. Drag-to-snap *release* is animated because it goes through `WindowManager.execute` after the mouse is up.

**Test command** (about 15 s incremental; the first run builds everything):

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/<TestClass> CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

**Build command** for the app itself (ad-hoc signed Debug build, needed for manual checks):

```bash
xcodebuild build -project Rectangle.xcodeproj -scheme Rectangle -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "error:|warning: .*WindowAnimation|\*\* BUILD"
```

The built app is at `~/Library/Developer/Xcode/DerivedData/Rectangle-*/Build/Products/Debug/Rectangle.app`.

---

## File structure

| File | Responsibility |
|---|---|
| `Rectangle/WindowAnimation/WindowAnimationGeometry.swift` (new) | Pure policy and geometry: enable decision, duration clamp, overlay rect, ghost frame conversion, moved-window filter. No AppKit windows, no AX. |
| `Rectangle/WindowAnimation/WindowSnapshot.swift` (new) | `WindowSnapshotProvider` protocol and the CoreGraphics implementation. Only file that calls capture APIs. |
| `Rectangle/WindowAnimation/GhostOverlayWindow.swift` (new) | `GhostOverlayPresenting` protocol and the `NSPanel` implementation with Core Animation. Only file that knows about layers. |
| `Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift` (new) | Permission preflight, request, and the guidance alert. |
| `Rectangle/WindowAnimation/WindowAnimator.swift` (new) | `WindowFrameSource` protocol, `WindowAnimationSettings`, `WindowMoveTransaction`, `WindowAnimator` singleton. Orchestrates begin / include / end. |
| `Rectangle/Defaults.swift` (modify) | Two new defaults. |
| `Rectangle/WindowManager.swift` (modify) | Begin the transaction before applying, end it in `postProcess`, wrap Restore. |
| `Rectangle/WindowManager+CooperativeCornerResize.swift` (modify) | `include` neighbours before they move; pass `animation` through the copied `ResultParameters`. |
| `Rectangle/MultiWindow/MultiWindowManager.swift`, `ReverseAllManager.swift`, `Rectangle/TodoMode/TodoManager.swift` (modify) | Wrap their move loops in a transaction. |
| `Rectangle/PrefsWindow/SettingsViewController.swift` (modify) | Checkbox in the Extras popover. |
| `Rectangle/mul.lproj/Main.xcstrings` (modify) | New string keys. |
| `TerminalCommands.md` (modify) | Document the two defaults. |
| `RectangleTests/WindowAnimationTests.swift` (new) | All unit tests for this feature. |

Fixed pbxproj object ids used by this plan (prefix `7A11A1`, verified absent from the project):

| Object | Id |
|---|---|
| Group `WindowAnimation` | `7A11A1FF000000000000000A` |
| `WindowAnimationGeometry.swift` | ref `7A11A1000000000000000101`, build `7A11A1010000000000000101` |
| `WindowSnapshot.swift` | ref `7A11A1000000000000000102`, build `7A11A1010000000000000102` |
| `GhostOverlayWindow.swift` | ref `7A11A1000000000000000103`, build `7A11A1010000000000000103` |
| `ScreenRecordingAuthorization.swift` | ref `7A11A1000000000000000104`, build `7A11A1010000000000000104` |
| `WindowAnimator.swift` | ref `7A11A1000000000000000105`, build `7A11A1010000000000000105` |
| `WindowAnimationTests.swift` | ref `7A11A1000000000000000201`, build `7A11A1010000000000000201` |

Existing ids you will pass to the script: Rectangle app group `9824700B22AF9B7D0037B409`, Rectangle app Sources phase `9824700522AF9B7D0037B409`, RectangleTests group `9824701E22AF9B7E0037B409`, RectangleTests Sources phase `9824701722AF9B7E0037B409`.

---

### Task 1: Throwaway capture probe and project scaffolding

Confirms on this Mac (macOS 26.6) that CoreGraphics window capture still returns pixels, and sets up the pbxproj helper, the `WindowAnimation` group, the test file, and the two defaults.

**Files:**
- Create (throwaway, outside the repo): `/private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/probe/probe.swift`
- Create (throwaway, outside the repo): `/private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py`
- Modify: `Rectangle.xcodeproj/project.pbxproj`
- Modify: `Rectangle/Defaults.swift:51` (after `footprintColor`) and `Rectangle/Defaults.swift:194` (after `footprintAnimationDurationMultiplier,` in `array`)
- Modify: `TerminalCommands.md`
- Create: `RectangleTests/WindowAnimationTests.swift`

**Interfaces:**
- Produces: `Defaults.windowAnimation: BoolDefault`, `Defaults.windowAnimationDuration: FloatDefault` (default 0.22); the `add_to_pbxproj.py` helper; the `WindowAnimation` group.

- [ ] **Step 1: Write the capture probe**

`/private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad` is the session scratchpad directory. Create `/private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/probe/probe.swift`:

```swift
import Cocoa

// Throwaway probe: does CGWindowListCreateImage still return pixels for another app's window,
// and does the from-array variant give a backdrop without that window? Writes two PNGs next to the binary.

func savePNG(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name)
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.path)
}

func opaqueFraction(_ image: CGImage) -> Double {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var sampled = 0, opaque = 0
    var i = 3
    while i < w * h * 4 { sampled += 1; if data[i] > 0 { opaque += 1 }; i += 4 * 97 }
    return Double(opaque) / Double(max(sampled, 1))
}

print("preflight:", CGPreflightScreenCaptureAccess())
if !CGPreflightScreenCaptureAccess() {
    print("requesting access (returns false while macOS prompts); grant it, then rerun")
    print("request result:", CGRequestScreenCaptureAccess())
    exit(1)
}

let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let me = Int32(ProcessInfo.processInfo.processIdentifier)
guard let target = infos.first(where: {
    ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? Int32) != me
}) else { print("no normal window found"); exit(1) }
let targetId = CGWindowID(target[kCGWindowNumber as String] as! Int)
print("target:", target[kCGWindowOwnerName as String] ?? "?", targetId, target[kCGWindowBounds as String] ?? "")

guard let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, targetId, [.boundsIgnoreFraming, .bestResolution]) else {
    print("WINDOW CAPTURE FAILED"); exit(1)
}
print("window image:", windowImage.width, "x", windowImage.height, "opaque fraction:", opaqueFraction(windowImage))
savePNG(windowImage, "window.png")

let ids = infos.compactMap { $0[kCGWindowNumber as String] as? Int }.filter { $0 != Int(targetId) }
let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: ids.count)
for (i, id) in ids.enumerated() { values[i] = UnsafeRawPointer(bitPattern: UInt(id)) }
let array = CFArrayCreate(kCFAllocatorDefault, values, ids.count, nil)!
let screen = NSScreen.screens[0].frame
let cgScreen = CGRect(x: screen.minX, y: 0, width: screen.width, height: screen.height)
guard let backdrop = CGWindowListCreateImageFromArray(cgScreen, array, [.bestResolution]) else {
    print("BACKDROP CAPTURE FAILED"); exit(1)
}
print("backdrop image:", backdrop.width, "x", backdrop.height, "opaque fraction:", opaqueFraction(backdrop))
savePNG(backdrop, "backdrop.png")
```

- [ ] **Step 2: Compile and run the probe**

Run from the probe directory:

```bash
cd /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/probe && swiftc -O probe.swift -o probe && ./probe
```

Expected on first run without permission: `preflight: false`, a macOS prompt for the app hosting your shell (Terminal or the Claude desktop app). Grant it, restart that host app if macOS asks, rerun.

Expected with permission: `window image: <w> x <h> opaque fraction: >0.5` and `backdrop image: ... opaque fraction: ~1.0`, plus two PNGs. Use the Read tool on `window.png` (should show only the target window, transparent rounded corners) and `backdrop.png` (should show the desktop with that window missing, other windows and the wallpaper present).

If the window image is blank or the call returns nil despite `preflight: true`, stop and report: the capture path is not viable on this OS and the design needs the ScreenCaptureKit path instead. Do not proceed to later tasks.

- [ ] **Step 3: Create the pbxproj helper script**

Create `/private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py`:

```python
#!/usr/bin/env python3
"""Register a Swift source file in Rectangle.xcodeproj.

usage: add_to_pbxproj.py <file name> <group id> <sources phase id> <file ref id> <build file id>
Run from the repo root. Idempotent: does nothing if the file ref id already exists.
"""
import sys

PBXPROJ = "Rectangle.xcodeproj/project.pbxproj"
name, group_id, phase_id, ref_id, build_id = sys.argv[1:6]

with open(PBXPROJ) as f:
    s = f.read()

if ref_id in s:
    print("already registered:", name)
    sys.exit(0)

def insert_after_list_open(text, obj_id, list_key, line):
    start = text.index(f"\t\t{obj_id} /*")
    marker = f"{list_key} = (\n"
    at = text.index(marker, start) + len(marker)
    return text[:at] + line + text[at:]

s = s.replace(
    "/* Begin PBXBuildFile section */\n",
    f"/* Begin PBXBuildFile section */\n\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n",
    1,
)
s = s.replace(
    "/* Begin PBXFileReference section */\n",
    f"/* Begin PBXFileReference section */\n\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n",
    1,
)
s = insert_after_list_open(s, group_id, "children", f"\t\t\t\t{ref_id} /* {name} */,\n")
s = insert_after_list_open(s, phase_id, "files", f"\t\t\t\t{build_id} /* {name} in Sources */,\n")

with open(PBXPROJ, "w") as f:
    f.write(s)
print("registered:", name)
```

- [ ] **Step 4: Add the WindowAnimation group to the project**

Run from the repo root:

```bash
python3 - <<'EOF'
p = "Rectangle.xcodeproj/project.pbxproj"
s = open(p).read()
assert "7A11A1FF000000000000000A" not in s
group = ('\t\t7A11A1FF000000000000000A /* WindowAnimation */ = {\n'
         '\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n'
         '\t\t\tpath = WindowAnimation;\n\t\t\tsourceTree = "<group>";\n\t\t};\n')
s = s.replace("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n" + group, 1)
start = s.index("\t\t9824700B22AF9B7D0037B409 /* Rectangle */ = {")
at = s.index("children = (\n", start) + len("children = (\n")
s = s[:at] + "\t\t\t\t7A11A1FF000000000000000A /* WindowAnimation */,\n" + s[at:]
open(p, "w").write(s)
print("group added")
EOF
mkdir -p Rectangle/WindowAnimation
```

- [ ] **Step 5: Add the defaults**

In `Rectangle/Defaults.swift`, after the line `static let footprintColor = JSONDefault<CodableColor>(key: "footprintColor")` add:

```swift
    static let windowAnimation = BoolDefault(key: "windowAnimation")
    static let windowAnimationDuration = FloatDefault(key: "windowAnimationDuration", defaultValue: 0.22)
```

In the same file, inside `static var array: [Default] = [`, after the line `footprintAnimationDurationMultiplier,` add:

```swift
        windowAnimation,
        windowAnimationDuration,
```

- [ ] **Step 6: Write the failing defaults test**

Create `RectangleTests/WindowAnimationTests.swift`:

```swift
/// WindowAnimationTests.swift

import XCTest
@testable import Rectangle

final class WindowAnimationDefaultsTests: XCTestCase {

    func testDefaultsUseTheDocumentedKeys() {
        XCTAssertEqual(Defaults.windowAnimation.key, "windowAnimation")
        XCTAssertEqual(Defaults.windowAnimationDuration.key, "windowAnimationDuration")
    }

    func testDefaultsAreRegisteredForImportAndExport() {
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimation" })
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimationDuration" })
    }
}
```

Register it in the test target:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py WindowAnimationTests.swift 9824701E22AF9B7E0037B409 9824701722AF9B7E0037B409 7A11A1000000000000000201 7A11A1010000000000000201
```

- [ ] **Step 7: Run the test**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/WindowAnimationDefaultsTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

Expected: both tests pass (`** TEST SUCCEEDED **`). If the build fails with "Cannot find 'WindowAnimationDefaultsTests'", the pbxproj registration did not land; inspect `git diff Rectangle.xcodeproj/project.pbxproj`.

- [ ] **Step 8: Document the defaults**

In `TerminalCommands.md`, add to the contents list after the line `- [Modify the "footprint" displayed for drag to snap area](#modify-the-footprint-displayed-for-drag-to-snap-area)`:

```markdown
- [Animate window movement](#animate-window-movement)
```

Add this section right before the `## Move Up/Down/Left/Right: Don't center on edge` heading:

````markdown
## Animate window movement

Rectangle can animate a window gliding and scaling into its new position, similar to Windows 11 snap animations. This is off by default and can be toggled with the "Animate window movement" checkbox at the bottom of the "Extras" popover in the General tab of the Settings window.

The animation needs the Screen Recording permission, because Rectangle takes a snapshot of the window to animate it. macOS 15 and later periodically remind you that Rectangle can record the screen; that reminder is expected. Windows move instantly (as before) whenever the permission is missing or "Reduce motion" is enabled in System Settings.

```bash
defaults write com.knollsoft.Rectangle windowAnimation -bool true
```

The duration in seconds (default 0.22, clamped between 0.05 and 1):

```bash
defaults write com.knollsoft.Rectangle windowAnimationDuration -float 0.3
```
````

- [ ] **Step 9: Commit**

```bash
git add Rectangle.xcodeproj/project.pbxproj Rectangle/Defaults.swift RectangleTests/WindowAnimationTests.swift TerminalCommands.md
git commit -m "Add window animation defaults, test file, and project group

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: WindowAnimationGeometry

Pure policy and geometry. Everything here is unit tested.

**Files:**
- Create: `Rectangle/WindowAnimation/WindowAnimationGeometry.swift`
- Modify: `Rectangle.xcodeproj/project.pbxproj` (via script)
- Test: `RectangleTests/WindowAnimationTests.swift`

**Interfaces:**
- Produces:
  - `WindowAnimationGeometry.shouldAnimate(enabled: Bool, hasPermission: Bool, reduceMotion: Bool) -> Bool`
  - `WindowAnimationGeometry.clampedDuration(_ requested: Double) -> Double`
  - `WindowAnimationGeometry.isCapturable(windowId: CGWindowID) -> Bool`
  - `WindowAnimationGeometry.overlayRect(screenFrames: [CGRect], touching rects: [CGRect]) -> CGRect`
  - `WindowAnimationGeometry.ghostFrame(_ frame: CGRect, inOverlay overlayRect: CGRect) -> CGRect`
  - `WindowAnimationGeometry.movedWindowIds(start: [CGWindowID: CGRect], final: [CGWindowID: CGRect]) -> [CGWindowID]`
  - constants `fadeStartFraction`, `minimumDuration`, `maximumDuration`

- [ ] **Step 1: Write the failing tests**

Append to `RectangleTests/WindowAnimationTests.swift`:

```swift
final class WindowAnimationGeometryTests: XCTestCase {

    func testAnimatesOnlyWhenEnabledPermittedAndMotionAllowed() {
        XCTAssertTrue(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: true, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: false, hasPermission: true, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: false, reduceMotion: false))
        XCTAssertFalse(WindowAnimationGeometry.shouldAnimate(enabled: true, hasPermission: true, reduceMotion: true))
    }

    func testDurationIsClampedToASensibleRange() {
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(0.22), 0.22, accuracy: 0.0001)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(0), WindowAnimationGeometry.minimumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(-1), WindowAnimationGeometry.minimumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(5), WindowAnimationGeometry.maximumDuration)
        XCTAssertEqual(WindowAnimationGeometry.clampedDuration(.nan), WindowAnimationGeometry.minimumDuration)
    }

    func testDerivedAndZeroWindowIdsAreNotCapturable() {
        XCTAssertTrue(WindowAnimationGeometry.isCapturable(windowId: 1234))
        XCTAssertFalse(WindowAnimationGeometry.isCapturable(windowId: 0))
        XCTAssertFalse(WindowAnimationGeometry.isCapturable(windowId: AccessibilityElement.deriveWindowId(fromElementHash: 42)))
    }

    func testOverlayCoversOnlyTheScreensTheMoveTouches() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 100, y: 100, width: 200, height: 200)]),
                       left)
        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 100, y: 100, width: 200, height: 200),
                                                                      CGRect(x: 1100, y: 100, width: 200, height: 200)]),
                       left.union(right))
    }

    func testOverlayFallsBackToEveryScreenWhenNothingIsTouched() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right],
                                                           touching: [CGRect(x: 5000, y: 5000, width: 10, height: 10)]),
                       left.union(right))
        XCTAssertEqual(WindowAnimationGeometry.overlayRect(screenFrames: [left, right], touching: [.null]),
                       left.union(right))
        XCTAssertTrue(WindowAnimationGeometry.overlayRect(screenFrames: [], touching: [left]).isNull)
    }

    func testGhostFrameIsRelativeToTheOverlayOrigin() {
        let overlay = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: 1100, y: 50, width: 300, height: 200)

        XCTAssertEqual(WindowAnimationGeometry.ghostFrame(frame, inOverlay: overlay),
                       CGRect(x: 100, y: 50, width: 300, height: 200))
    }

    func testMovedWindowIdsIgnoresUnchangedMissingAndNullFinalFrames() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 200, y: 0, width: 100, height: 100)
        let start: [CGWindowID: CGRect] = [1: a, 2: b, 3: a, 4: a]
        let final: [CGWindowID: CGRect] = [1: b, 2: b, 3: .null]

        XCTAssertEqual(WindowAnimationGeometry.movedWindowIds(start: start, final: final), [1])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/WindowAnimationGeometryTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

Expected: build error `cannot find 'WindowAnimationGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Rectangle/WindowAnimation/WindowAnimationGeometry.swift`:

```swift
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
```

Register it:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py WindowAnimationGeometry.swift 7A11A1FF000000000000000A 9824700522AF9B7D0037B409 7A11A1000000000000000101 7A11A1010000000000000101
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: 7 tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Rectangle/WindowAnimation/WindowAnimationGeometry.swift Rectangle.xcodeproj/project.pbxproj RectangleTests/WindowAnimationTests.swift
git commit -m "Add pure geometry and policy for the window move animation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: WindowSnapshot capture provider

The only code that talks to the capture APIs, behind a protocol so the animator can be tested with a fake.

**Files:**
- Create: `Rectangle/WindowAnimation/WindowSnapshot.swift`
- Modify: `Rectangle.xcodeproj/project.pbxproj` (via script)
- Test: `RectangleTests/WindowAnimationTests.swift`

**Interfaces:**
- Produces:
  - `protocol WindowSnapshotProvider { func windowImage(windowId: CGWindowID) -> CGImage?; func backdropImage(rect: CGRect, excluding: Set<CGWindowID>) -> CGImage? }` (rect in CoreGraphics global coordinates, origin top-left of the main display, i.e. the same space as AX frames)
  - `struct CGWindowSnapshotProvider: WindowSnapshotProvider`
  - `WindowSnapshot.backdropWindowIds(onScreen: [CGWindowID], excluding: Set<CGWindowID>) -> [CGWindowID]`
  - `WindowSnapshot.onScreenWindowIds() -> [CGWindowID]`

- [ ] **Step 1: Write the failing test**

Append to `RectangleTests/WindowAnimationTests.swift`:

```swift
final class WindowSnapshotTests: XCTestCase {

    func testBackdropKeepsFrontToBackOrderAndDropsExcludedWindows() {
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [50, 40, 30, 20], excluding: [40, 20]), [50, 30])
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [50, 40], excluding: []), [50, 40])
        XCTAssertEqual(WindowSnapshot.backdropWindowIds(onScreen: [], excluding: [1]), [])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/WindowSnapshotTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

Expected: build error `cannot find 'WindowSnapshot' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Rectangle/WindowAnimation/WindowSnapshot.swift`:

```swift
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

    /// Every on-screen window front to back, including the desktop picture, unlike `WindowUtil.getWindowList`.
    static func onScreenWindowIds() -> [CGWindowID] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            (info[kCGWindowNumber as String] as? NSNumber).map { CGWindowID(truncating: $0) }
        }
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
              let image = CGWindowListCreateImageFromArray(rect, array, [.bestResolution]),
              image.width > 1, image.height > 1
        else {
            Logger.log("Window animation: could not capture backdrop \(rect.debugDescription)")
            return nil
        }
        return image
    }
}
```

Register it:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py WindowSnapshot.swift 7A11A1FF000000000000000A 9824700522AF9B7D0037B409 7A11A1000000000000000102 7A11A1010000000000000102
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: 1 test passes. Deprecation warnings for `CGWindowListCreateImage` are expected and acceptable; there must be no errors.

- [ ] **Step 5: Commit**

```bash
git add Rectangle/WindowAnimation/WindowSnapshot.swift Rectangle.xcodeproj/project.pbxproj RectangleTests/WindowAnimationTests.swift
git commit -m "Add CoreGraphics window snapshot provider for the move animation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: GhostOverlayWindow

The overlay panel: backdrop layer plus one ghost layer per window, Core Animation for the glide, an alpha fade at the end.

**Files:**
- Create: `Rectangle/WindowAnimation/GhostOverlayWindow.swift`
- Modify: `Rectangle.xcodeproj/project.pbxproj` (via script)
- Test: `RectangleTests/WindowAnimationTests.swift`

**Interfaces:**
- Consumes: `WindowAnimationGeometry.fadeStartFraction`.
- Produces:
  - `struct GhostSpec { let id: CGWindowID; let image: CGImage; let startFrame: CGRect }` (frame in overlay-local AppKit coordinates)
  - `protocol GhostOverlayPresenting: AnyObject { var overlayWindowId: CGWindowID { get }; func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec]); func updateBackdrop(_ image: CGImage?); func addGhost(_ ghost: GhostSpec); func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void); func dismiss() }`
  - `final class GhostOverlayWindow: NSPanel, GhostOverlayPresenting`, plus `var ghostCount: Int` for tests.

- [ ] **Step 1: Write the failing tests**

Append to `RectangleTests/WindowAnimationTests.swift`:

```swift
/// A tiny opaque image for tests that need a CGImage.
func makeTestImage(width: Int = 4, height: Int = 4) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

final class GhostOverlayWindowTests: XCTestCase {

    func testOverlayNeverTakesFocusOrMouseInput() {
        let overlay = GhostOverlayWindow()

        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.canBecomeKey)
        XCTAssertFalse(overlay.hidesOnDeactivate)
        XCTAssertFalse(overlay.hasShadow)
        XCTAssertEqual(overlay.level, .floating)
        XCTAssertTrue(overlay.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(overlay.isVisible)
        XCTAssertGreaterThan(overlay.overlayWindowId, 0)
    }

    func testPresentShowsGhostsAndDismissClearsThem() {
        let overlay = GhostOverlayWindow()
        let ghost = GhostSpec(id: 7, image: makeTestImage(), startFrame: CGRect(x: 10, y: 10, width: 40, height: 40))

        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: makeTestImage(), ghosts: [ghost])
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 1)

        overlay.addGhost(GhostSpec(id: 8, image: makeTestImage(), startFrame: CGRect(x: 60, y: 10, width: 40, height: 40)))
        XCTAssertEqual(overlay.ghostCount, 2)

        overlay.dismiss()
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
        XCTAssertEqual(overlay.alphaValue, 1)
    }

    func testAnimateDropsGhostsThatAreNotMovingAndCompletes() {
        let overlay = GhostOverlayWindow()
        let moving = GhostSpec(id: 1, image: makeTestImage(), startFrame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let still = GhostSpec(id: 2, image: makeTestImage(), startFrame: CGRect(x: 100, y: 0, width: 40, height: 40))
        overlay.present(overlayFrame: CGRect(x: 0, y: 0, width: 200, height: 200), backdrop: nil, ghosts: [moving, still])

        let completed = expectation(description: "animation completed")
        overlay.animate(endFrames: [1: CGRect(x: 50, y: 50, width: 80, height: 80)], removing: [2], duration: 0.05) {
            completed.fulfill()
        }
        XCTAssertEqual(overlay.ghostCount, 1)

        wait(for: [completed], timeout: 2)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(overlay.ghostCount, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/GhostOverlayWindowTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

Expected: build error `cannot find 'GhostOverlayWindow' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Rectangle/WindowAnimation/GhostOverlayWindow.swift`:

```swift
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
    /// Glides the ghosts in `endFrames` to their new frames, removes the ghosts in `removing`,
    /// fades the overlay out over the last part of `duration`, then hides it and calls `completion`.
    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void)
    /// Hides the overlay immediately, cancelling any running animation. Its completion is not called.
    func dismiss()
}

final class GhostOverlayWindow: NSPanel, GhostOverlayPresenting {

    private let backdropLayer = CALayer()
    private var ghostLayers: [CGWindowID: CALayer] = [:]
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
        alphaValue = 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.frame = CGRect(origin: .zero, size: overlayFrame.size)
        backdropLayer.contentsScale = backingScaleFactor
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

        // Standalone layers animate bounds and position implicitly with the transaction's timing.
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.1, 0.9, 0.2, 1))
        for (id, end) in endFrames {
            guard let layer = ghostLayers[id] else { continue }
            layer.bounds = CGRect(origin: .zero, size: end.size)
            layer.position = CGPoint(x: end.midX, y: end.midY)
        }
        CATransaction.commit()

        let fadeDelay = duration * WindowAnimationGeometry.fadeStartFraction
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) { [weak self] in
            guard let self, self.generation == thisGeneration else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration - fadeDelay
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == thisGeneration else { return }
                self.dismiss()
                completion()
            })
        }
    }

    func dismiss() {
        generation += 1
        orderOut(nil)
        alphaValue = 1
        clearGhosts()
        backdropLayer.contents = nil
    }

    private func addGhostLayer(_ ghost: GhostSpec) {
        let layer = CALayer()
        layer.contents = ghost.image
        layer.contentsGravity = .resize
        layer.contentsScale = backingScaleFactor
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
```

Register it:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py GhostOverlayWindow.swift 7A11A1FF000000000000000A 9824700522AF9B7D0037B409 7A11A1000000000000000103 7A11A1010000000000000103
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: 3 tests pass. The test host app will briefly show a small window; that is the overlay and is expected.

If `testOverlayNeverTakesFocusOrMouseInput` fails on `overlayWindowId`, `windowNumber` was not assigned at init on this OS; change `overlayWindowId` to order the window out-of-screen once (`orderFrontRegardless(); orderOut(nil)`) inside `init()` before the id is read, and rerun.

- [ ] **Step 5: Commit**

```bash
git add Rectangle/WindowAnimation/GhostOverlayWindow.swift Rectangle.xcodeproj/project.pbxproj RectangleTests/WindowAnimationTests.swift
git commit -m "Add the ghost overlay panel for the window move animation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Screen Recording authorization helper (preflight only)

Small file now so the animator can depend on it; the request flow and alert come in Task 9.

**Files:**
- Create: `Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift`
- Modify: `Rectangle.xcodeproj/project.pbxproj` (via script)

**Interfaces:**
- Produces: `enum ScreenRecordingAuthorization { static var hasAccess: Bool }`

- [ ] **Step 1: Write the file**

Create `Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift`:

```swift
/// ScreenRecordingAuthorization.swift

import Cocoa

/// Screen Recording permission, needed to capture other apps' windows for the move animation.
enum ScreenRecordingAuthorization {

    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }
}
```

Register it:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py ScreenRecordingAuthorization.swift 7A11A1FF000000000000000A 9824700522AF9B7D0037B409 7A11A1000000000000000104 7A11A1010000000000000104
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -project Rectangle.xcodeproj -scheme Rectangle -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift Rectangle.xcodeproj/project.pbxproj
git commit -m "Add Screen Recording permission preflight

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: WindowAnimator and WindowMoveTransaction

The orchestrator. Tested entirely with fakes.

**Files:**
- Create: `Rectangle/WindowAnimation/WindowAnimator.swift`
- Modify: `Rectangle.xcodeproj/project.pbxproj` (via script)
- Test: `RectangleTests/WindowAnimationTests.swift`

**Interfaces:**
- Consumes: `WindowAnimationGeometry`, `WindowSnapshotProvider`, `CGWindowSnapshotProvider`, `GhostOverlayPresenting`, `GhostOverlayWindow`, `GhostSpec`, `ScreenRecordingAuthorization.hasAccess`, `Defaults.windowAnimation`, `Defaults.windowAnimationDuration`, `CGRect.screenFlipped`, `AccessibilityElement.getWindowId()`.
- Produces:
  - `protocol WindowFrameSource: AnyObject { func animationWindowId() -> CGWindowID?; var frame: CGRect { get } }`, with `extension AccessibilityElement: WindowFrameSource`.
  - `struct WindowAnimationSettings` with closures `isEnabled`, `hasPermission`, `reduceMotion`, `duration`, `screenFrames`, and `static let live`.
  - `final class WindowMoveTransaction { func include(_ window: WindowFrameSource); func end(); func cancel(); var isFinished: Bool; var windowIds: [CGWindowID] }`
  - `final class WindowAnimator { static let shared; init(snapshots:presenterFactory:settings:); func begin(windows: [WindowFrameSource], covering rects: [CGRect]) -> WindowMoveTransaction?; func include(_ window: WindowFrameSource); func perform(windows: [WindowFrameSource], covering rects: [CGRect], _ body: () -> Void); func cancelCurrent() }`. `rects` are AppKit coordinates (what Rectangle calls "screenFlipped" or "normalized").

- [ ] **Step 1: Write the failing tests**

Append to `RectangleTests/WindowAnimationTests.swift`:

```swift
final class FakeWindow: WindowFrameSource {
    var id: CGWindowID?
    var frame: CGRect

    init(id: CGWindowID?, frame: CGRect) {
        self.id = id
        self.frame = frame
    }

    func animationWindowId() -> CGWindowID? { id }
}

final class FakeSnapshots: WindowSnapshotProvider {
    var failingWindowIds: Set<CGWindowID> = []
    var failBackdrop = false
    var windowCaptures: [CGWindowID] = []
    var backdropCaptures: [(rect: CGRect, excluding: Set<CGWindowID>)] = []

    func windowImage(windowId: CGWindowID) -> CGImage? {
        windowCaptures.append(windowId)
        return failingWindowIds.contains(windowId) ? nil : makeTestImage()
    }

    func backdropImage(rect: CGRect, excluding: Set<CGWindowID>) -> CGImage? {
        backdropCaptures.append((rect, excluding))
        return failBackdrop ? nil : makeTestImage()
    }
}

final class FakePresenter: GhostOverlayPresenting {
    let overlayWindowId: CGWindowID = 999
    var presentations: [(frame: CGRect, ghosts: [GhostSpec])] = []
    var backdropUpdates = 0
    var addedGhosts: [GhostSpec] = []
    var animations: [(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double)] = []
    var dismissCount = 0

    func present(overlayFrame: CGRect, backdrop: CGImage?, ghosts: [GhostSpec]) {
        presentations.append((overlayFrame, ghosts))
    }

    func updateBackdrop(_ image: CGImage?) { backdropUpdates += 1 }
    func addGhost(_ ghost: GhostSpec) { addedGhosts.append(ghost) }

    func animate(endFrames: [CGWindowID: CGRect], removing: Set<CGWindowID>, duration: Double, completion: @escaping () -> Void) {
        animations.append((endFrames, removing, duration))
        completion()
    }

    func dismiss() { dismissCount += 1 }
}

final class WindowAnimatorTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let a = CGRect(x: 10, y: 10, width: 300, height: 200)
    private let b = CGRect(x: 500, y: 10, width: 300, height: 200)

    private func makeAnimator(enabled: Bool = true, permission: Bool = true, reduceMotion: Bool = false,
                              duration: Double = 0.22) -> (WindowAnimator, FakeSnapshots, FakePresenter) {
        let snapshots = FakeSnapshots()
        let presenter = FakePresenter()
        let settings = WindowAnimationSettings(isEnabled: { enabled },
                                               hasPermission: { permission },
                                               reduceMotion: { reduceMotion },
                                               duration: { duration },
                                               screenFrames: { [self.screen] })
        let animator = WindowAnimator(snapshots: snapshots, presenterFactory: { presenter }, settings: settings)
        return (animator, snapshots, presenter)
    }

    func testBeginDoesNothingWhenAnimationIsNotAllowed() {
        for (animator, _, presenter) in [makeAnimator(enabled: false), makeAnimator(permission: false), makeAnimator(reduceMotion: true)] {
            XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))
            XCTAssertTrue(presenter.presentations.isEmpty)
        }
    }

    func testBeginCapturesEveryWindowAndPresentsTheOverlayOverTheirScreen() {
        let (animator, snapshots, presenter) = makeAnimator()

        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a), FakeWindow(id: 2, frame: b)], covering: [a])

        XCTAssertNotNil(transaction)
        XCTAssertEqual(transaction?.windowIds, [1, 2])
        XCTAssertEqual(snapshots.windowCaptures, [1, 2])
        XCTAssertEqual(snapshots.backdropCaptures.count, 1)
        XCTAssertEqual(snapshots.backdropCaptures[0].excluding, [1, 2, 999])
        XCTAssertEqual(snapshots.backdropCaptures[0].rect, screen.screenFlipped)
        XCTAssertEqual(presenter.presentations.count, 1)
        XCTAssertEqual(presenter.presentations[0].frame, screen)
        XCTAssertEqual(presenter.presentations[0].ghosts.map(\.id), [1, 2])
    }

    func testWindowsThatCannotBeCapturedAreLeftOut() {
        let (animator, snapshots, presenter) = makeAnimator()
        snapshots.failingWindowIds = [3]
        let derived = AccessibilityElement.deriveWindowId(fromElementHash: 5)

        let transaction = animator.begin(windows: [FakeWindow(id: nil, frame: a),
                                                   FakeWindow(id: derived, frame: a),
                                                   FakeWindow(id: 3, frame: a),
                                                   FakeWindow(id: 4, frame: .null),
                                                   FakeWindow(id: 5, frame: b)],
                                         covering: [a])

        XCTAssertEqual(transaction?.windowIds, [5])
        XCTAssertEqual(presenter.presentations[0].ghosts.map(\.id), [5])
    }

    func testBeginIsAbortedWhenNothingOrNoBackdropCanBeCaptured() {
        let (animator, snapshots, presenter) = makeAnimator()
        snapshots.failingWindowIds = [1]
        XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))

        snapshots.failingWindowIds = []
        snapshots.failBackdrop = true
        XCTAssertNil(animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a]))

        XCTAssertTrue(presenter.presentations.isEmpty)
    }

    func testEndAnimatesOnlyTheWindowsThatMoved() {
        let (animator, _, presenter) = makeAnimator()
        let moving = FakeWindow(id: 1, frame: a)
        let still = FakeWindow(id: 2, frame: b)
        let transaction = animator.begin(windows: [moving, still], covering: [a])!

        moving.frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        transaction.end()

        XCTAssertEqual(presenter.animations.count, 1)
        XCTAssertEqual(Array(presenter.animations[0].endFrames.keys), [1])
        XCTAssertEqual(presenter.animations[0].endFrames[1],
                       WindowAnimationGeometry.ghostFrame(moving.frame.screenFlipped, inOverlay: screen))
        XCTAssertEqual(presenter.animations[0].removing, [2])
        XCTAssertEqual(presenter.animations[0].duration, 0.22, accuracy: 0.0001)
        XCTAssertTrue(transaction.isFinished)
    }

    func testEndWithoutAnyMovementJustHidesTheOverlay() {
        let (animator, _, presenter) = makeAnimator()
        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a])!

        transaction.end()

        XCTAssertTrue(presenter.animations.isEmpty)
        XCTAssertEqual(presenter.dismissCount, 1)
    }

    func testEndIsIdempotent() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let transaction = animator.begin(windows: [window], covering: [a])!
        window.frame = b

        transaction.end()
        transaction.end()

        XCTAssertEqual(presenter.animations.count, 1)
    }

    func testANewTransactionCancelsTheRunningOne() {
        let (animator, _, presenter) = makeAnimator()
        let window = FakeWindow(id: 1, frame: a)
        let first = animator.begin(windows: [window], covering: [a])!

        let second = animator.begin(windows: [window], covering: [a])
        window.frame = b
        first.end()

        XCTAssertNotNil(second)
        XCTAssertTrue(first.isFinished)
        XCTAssertEqual(presenter.dismissCount, 1)
        XCTAssertTrue(presenter.animations.isEmpty, "a cancelled transaction must not animate")
        XCTAssertEqual(presenter.presentations.count, 2)
    }

    func testIncludeAddsAGhostAndRefreshesTheBackdrop() {
        let (animator, snapshots, presenter) = makeAnimator()
        let transaction = animator.begin(windows: [FakeWindow(id: 1, frame: a)], covering: [a])!

        animator.include(FakeWindow(id: 2, frame: b))
        animator.include(FakeWindow(id: 2, frame: b))

        XCTAssertEqual(transaction.windowIds, [1, 2])
        XCTAssertEqual(presenter.addedGhosts.map(\.id), [2])
        XCTAssertEqual(snapshots.backdropCaptures.count, 2)
        XCTAssertEqual(snapshots.backdropCaptures[1].excluding, [1, 2, 999])
        XCTAssertEqual(presenter.backdropUpdates, 1)

        transaction.end()
        animator.include(FakeWindow(id: 3, frame: b))
        XCTAssertEqual(transaction.windowIds, [1, 2], "include after end is ignored")
    }

    func testPerformWrapsTheBodyInATransaction() {
        let (animator, _, presenter) = makeAnimator(duration: 5)
        let window = FakeWindow(id: 1, frame: a)

        animator.perform(windows: [window], covering: [a]) {
            window.frame = b
        }

        XCTAssertEqual(presenter.animations.count, 1)
        XCTAssertEqual(presenter.animations[0].duration, WindowAnimationGeometry.maximumDuration)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' -only-testing:RectangleTests/WindowAnimatorTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Case|error:|\*\* TEST"
```

Expected: build error `cannot find type 'WindowFrameSource' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Rectangle/WindowAnimation/WindowAnimator.swift`:

```swift
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
```

Register it:

```bash
python3 /private/tmp/claude-501/-Users-dustin-projects-Rectangle/c78edf6c-21e0-4f54-b855-9a167c158519/scratchpad/add_to_pbxproj.py WindowAnimator.swift 7A11A1FF000000000000000A 9824700522AF9B7D0037B409 7A11A1000000000000000105 7A11A1010000000000000105
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: 10 tests pass.

Note on `testBeginCapturesEveryWindowAndPresentsTheOverlayOverTheirScreen`: `screen.screenFlipped` uses the real main screen height; the assertion compares against the same conversion, so it holds on any display.

- [ ] **Step 5: Run the whole test target once**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`, no failures.

- [ ] **Step 6: Commit**

```bash
git add Rectangle/WindowAnimation/WindowAnimator.swift Rectangle.xcodeproj/project.pbxproj RectangleTests/WindowAnimationTests.swift
git commit -m "Add the window move animator and its transaction

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Wire the animator into WindowManager

Covers keyboard shortcuts, menu, URL, title bar, drag-to-snap release, Restore, and cooperative corner resize (plan and cleanup). Also the first in-app check that the overlay hides the jump.

**Files:**
- Modify: `Rectangle/WindowManager.swift` (Restore branch around line 66-77; before `let resultParameters = ResultParameters(` around line 196; `struct ResultParameters` around line 307; `func postProcess` around line 270)
- Modify: `Rectangle/WindowManager+CooperativeCornerResize.swift` (`ResultParameters(` copy around line 1421; `apply(_ adjustments:)` around line 1241)

**Interfaces:**
- Consumes: `WindowAnimator.shared.begin(windows:covering:)`, `.perform(windows:covering:_:)`, `.include(_:)`, `WindowMoveTransaction.end()`, `CooperativeCornerApplicationPlan.adjustments: [CooperativeCornerWindowAdjustment]` (each has `.element: AccessibilityElement`).
- Produces: `ResultParameters.animation: WindowMoveTransaction?`.

- [ ] **Step 1: Add the transaction to ResultParameters**

In `Rectangle/WindowManager.swift`, change the struct to:

```swift
struct ResultParameters {
    let windowId: CGWindowID?
    let action: WindowAction
    let windowElement: AccessibilityElement
    let calcResult: WindowCalculationResult
    let usableScreens: UsableScreens
    let visibleFrameOfScreen: CGRect
    let source: ExecutionSource
    let isFixedSize: Bool
    /// The animated move this result belongs to; ended in `postProcess`.
    let animation: WindowMoveTransaction?
}
```

- [ ] **Step 2: Begin the transaction in execute and end it in postProcess**

In `execute`, replace:

```swift
        let resultParameters = ResultParameters(windowId: windowId,
                                                action: action,
                                                windowElement: frontmostWindowElement,
                                                calcResult: calcResult,
                                                usableScreens: sourceScreens,
                                                visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                                source: parameters.source,
                                                isFixedSize: isFixedSize)
```

with:

```swift
        var animatedWindows: [WindowFrameSource] = [frontmostWindowElement]
        if let cooperativeCornerPlan {
            animatedWindows += cooperativeCornerPlan.adjustments.map { $0.element as WindowFrameSource }
        }
        let animation = WindowAnimator.shared.begin(windows: animatedWindows,
                                                    covering: [currentNormalizedRect, calcResult.rect])

        let resultParameters = ResultParameters(windowId: windowId,
                                                action: action,
                                                windowElement: frontmostWindowElement,
                                                calcResult: calcResult,
                                                usableScreens: sourceScreens,
                                                visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                                source: parameters.source,
                                                isFixedSize: isFixedSize,
                                                animation: animation)
```

At the top of `func postProcess(result: ResultParameters, resultingRect: CGRect)`, before `let calcResult = result.calcResult`, add:

```swift
        result.animation?.end()
```

- [ ] **Step 3: Animate the Restore action**

In `execute`, replace:

```swift
            if let restoreRect = AppDelegate.windowHistory.restoreRects[windowId] {
                frontmostWindowElement.setFrame(restoreRect)
            }
```

with:

```swift
            if let restoreRect = AppDelegate.windowHistory.restoreRects[windowId] {
                WindowAnimator.shared.perform(windows: [frontmostWindowElement],
                                              covering: [frontmostWindowElement.frame.screenFlipped, restoreRect.screenFlipped]) {
                    frontmostWindowElement.setFrame(restoreRect)
                }
            }
```

- [ ] **Step 4: Pass the transaction through the cooperative copy and include neighbours**

In `Rectangle/WindowManager+CooperativeCornerResize.swift`, the `ResultParameters(` construction near line 1421 becomes:

```swift
            let focusedResult = ResultParameters(windowId: result.windowId,
                                                 action: result.action,
                                                 windowElement: result.windowElement,
                                                 calcResult: calcResult,
                                                 usableScreens: result.usableScreens,
                                                 visibleFrameOfScreen: result.visibleFrameOfScreen,
                                                 source: result.source,
                                                 isFixedSize: result.isFixedSize,
                                                 animation: result.animation)
```

In `private func apply(_ adjustments: [CooperativeCornerWindowAdjustment], ...)` near line 1241, replace:

```swift
                adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
```

with:

```swift
                WindowAnimator.shared.include(adjustment.element)
                adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
```

(`include` is a no-op for windows already in the transaction, so the plan's own adjustments captured at begin are not captured twice.)

- [ ] **Step 5: Build and run the full test target**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`. If the compiler reports a missing `animation:` argument anywhere else, add `animation: nil` there.

- [ ] **Step 6: In-app check that the overlay hides the jump**

Build the app (ad-hoc signed, so macOS can grant it permissions):

```bash
xcodebuild build -project Rectangle.xcodeproj -scheme Rectangle -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "error:|\*\* BUILD"
```

Then quit any running Rectangle and launch the build:

```bash
pkill -x Rectangle; open "$(ls -d ~/Library/Developer/Xcode/DerivedData/Rectangle-*/Build/Products/Debug/Rectangle.app | head -1)"
```

Grant Accessibility if prompted. Enable the feature from the terminal for now (the checkbox arrives in Task 9), then relaunch Rectangle:

```bash
defaults write com.knollsoft.Rectangle windowAnimation -bool true
```

Grant Screen Recording: open System Settings > Privacy & Security > Screen Recording, add the Debug `Rectangle.app`, relaunch Rectangle. Because the Debug build is ad-hoc signed, macOS may forget the grant after a rebuild; if moves stop animating after rebuilding, remove and re-add Rectangle in that list (or run `tccutil reset ScreenCapture com.knollsoft.Rectangle` and grant again).

Now press Rectangle's Left Half shortcut on a Finder window and watch. Expected: the window glides and scales into the left half with no visible jump before the glide. Then Right Half, Maximize, Restore.

If a one-frame jump to the destination is visible before the ghost starts moving, add `RunLoop.current.run(until: Date())` after `CATransaction.flush()` in `GhostOverlayWindow.present` to let the window server commit the overlay, rebuild, and check again. Record the outcome (which variant you kept) in the commit message.

- [ ] **Step 7: Commit**

```bash
git add Rectangle/WindowManager.swift Rectangle/WindowManager+CooperativeCornerResize.swift Rectangle/WindowAnimation/GhostOverlayWindow.swift
git commit -m "Animate window actions executed through WindowManager

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Animate multi-window, Reverse All, and Todo reflow

**Files:**
- Modify: `Rectangle/MultiWindow/MultiWindowManager.swift` (four `for` loops: `tileAllWindowsOnScreen`, `cascadeAllWindowsOnScreen`, `cascadeActiveAppWindowsOnScreen`, `tileActiveAppWindowsOnScreen`)
- Modify: `Rectangle/MultiWindow/ReverseAllManager.swift` (`reverseAll`)
- Modify: `Rectangle/TodoMode/TodoManager.swift` (`moveAll`)

**Interfaces:**
- Consumes: `WindowAnimator.shared.perform(windows:covering:_:)`. `[AccessibilityElement]` converts to `[WindowFrameSource]` implicitly.

- [ ] **Step 1: Tile all**

In `MultiWindowManager.tileAllWindowsOnScreen`, replace:

```swift
        for (ind, w) in windows.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
```

with:

```swift
        WindowAnimator.shared.perform(windows: windows, covering: [screens.currentScreen.frame]) {
            for (ind, w) in windows.enumerated() {
                let column = ind % Int(columns)
                let row = ind / Int(columns)
                tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
            }
        }
```

- [ ] **Step 2: Cascade all**

In `MultiWindowManager.cascadeAllWindowsOnScreen`, replace:

```swift
        for (ind, w) in windows.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
        }
```

with:

```swift
        WindowAnimator.shared.perform(windows: windows, covering: [screens.currentScreen.frame]) {
            for (ind, w) in windows.enumerated() {
                cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
            }
        }
```

- [ ] **Step 3: Cascade active app**

In `MultiWindowManager.cascadeActiveAppWindowsOnScreen`, replace:

```swift
        // cascade the filtered windows
        for (ind, w) in filtered.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind, cascadeParameters: cascadeParameters)
        }
```

with:

```swift
        // cascade the filtered windows
        WindowAnimator.shared.perform(windows: filtered, covering: [screens.currentScreen.frame]) {
            for (ind, w) in filtered.enumerated() {
                cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind, cascadeParameters: cascadeParameters)
            }
        }
```

- [ ] **Step 4: Tile active app**

In `MultiWindowManager.tileActiveAppWindowsOnScreen`, replace:

```swift
        for (ind, w) in filtered.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
```

with:

```swift
        WindowAnimator.shared.perform(windows: filtered, covering: [screens.currentScreen.frame]) {
            for (ind, w) in filtered.enumerated() {
                let column = ind % Int(columns)
                let row = ind / Int(columns)
                tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
            }
        }
```

- [ ] **Step 5: Reverse all**

In `ReverseAllManager.reverseAll`, replace:

```swift
        for w in windows {
            let wScreen = sd.detectScreens(using: w)?.currentScreen
            if Defaults.todo.userEnabled && TodoManager.isTodoWindow(w) { continue }
            if wScreen == currentScreen {
                reverseWindowPosition(w, screenFrame: screenFrame)
            }
        }
```

with:

```swift
        let windowsOnScreen = windows.filter { w in
            if Defaults.todo.userEnabled && TodoManager.isTodoWindow(w) { return false }
            return sd.detectScreens(using: w)?.currentScreen == currentScreen
        }

        WindowAnimator.shared.perform(windows: windowsOnScreen, covering: [currentScreen.frame]) {
            for w in windowsOnScreen {
                reverseWindowPosition(w, screenFrame: screenFrame)
            }
        }
```

- [ ] **Step 6: Todo reflow**

In `TodoManager.moveAll`, replace the block from `let sd = ScreenDetection()` through `todoWindow.setFrame(rect)` with:

```swift
                let sd = ScreenDetection()
                var adjustedVisibleFrame = screen.adjustedVisibleFrame()
                // Clear all windows from the todo app sidebar
                let windowsToShift = windows.filter { w in
                    w.getWindowId() != todoWindow.getWindowId()
                        && sd.detectScreens(using: w)?.currentScreen == TodoManager.todoScreen
                }

                WindowAnimator.shared.perform(windows: windowsToShift + [todoWindow], covering: [screen.frame]) {
                    for w in windowsToShift {
                        shiftWindowOffSidebar(w, screenVisibleFrame: adjustedVisibleFrame)
                    }

                    adjustedVisibleFrame = screen.adjustedVisibleFrame(true)
                    let sidebarWidth = getSidebarWidth(visibleFrameWidth: adjustedVisibleFrame.width)

                    var sharedEdge: Edge
                    var rect = adjustedVisibleFrame
                    let isRightSide = Defaults.todoSidebarSide.value == .right

                    sharedEdge = isRightSide ? .left : .right

                    if isRightSide {
                        rect.origin.x = adjustedVisibleFrame.maxX - sidebarWidth
                    }
                    rect.size.width = sidebarWidth

                    rect = rect.screenFlipped

                    if Defaults.gapSize.value > 0 {
                        rect = GapCalculation.applyGaps(rect, sharedEdges: sharedEdge, gapSize: Defaults.gapSize.value)
                    }
                    todoWindow.setFrame(rect)
                }
```

Leave the following `if bringToFront { todoWindow.bringToFront() }` as it is.

- [ ] **Step 7: Build and run the full test target**

```bash
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Rectangle/MultiWindow/MultiWindowManager.swift Rectangle/MultiWindow/ReverseAllManager.swift Rectangle/TodoMode/TodoManager.swift
git commit -m "Animate multi-window, Reverse All, and Todo reflow moves

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Permission request flow and the settings checkbox

**Files:**
- Modify: `Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift`
- Modify: `Rectangle/PrefsWindow/SettingsViewController.swift` (property list around line 54; toggle handlers around line 197; Extras popover after the `repeatedMaximizeCheckbox` block around line 990; state refresh around line 1210)
- Modify: `Rectangle/mul.lproj/Main.xcstrings`

**Interfaces:**
- Consumes: `ScreenRecordingAuthorization.hasAccess`, `Defaults.windowAnimation`.
- Produces: `ScreenRecordingAuthorization.requestIfNeeded() -> Bool` (discardable).

- [ ] **Step 1: Add the request flow**

Replace the contents of `Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift` with:

```swift
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
```

- [ ] **Step 2: Add the checkbox**

In `Rectangle/PrefsWindow/SettingsViewController.swift`:

After the line `private var repeatedMaximizeRestoresPreviousCheckbox: NSButton?` add:

```swift
    private var windowAnimationCheckbox: NSButton?
```

After the `toggleRepeatedMaximizeRestoresPrevious` handler add:

```swift
    @objc func toggleWindowAnimation(_ sender: NSButton) {
        let enabled = sender.state == .on
        Defaults.windowAnimation.enabled = enabled
        if enabled {
            ScreenRecordingAuthorization.requestIfNeeded()
        }
    }
```

After the line `repeatedMaximizeRestoresPreviousCheckbox = repeatedMaximizeCheckbox` (inside the Extras popover setup) add:

```swift
            let windowAnimationCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Animate window movement", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleWindowAnimation(_:)))
            windowAnimationCheckbox.state = Defaults.windowAnimation.enabled ? .on : .off
            windowAnimationCheckbox.toolTip = NSLocalizedString("Windows glide and scale into place, like Windows 11. Needs the Screen Recording permission; windows move instantly without it or when Reduce Motion is on.", tableName: "Main", value: "", comment: "")
            windowAnimationCheckbox.translatesAutoresizingMaskIntoConstraints = false
            windowAnimationCheckbox.alignment = .left

            mainStackView.addArrangedSubview(windowAnimationCheckbox)
            self.windowAnimationCheckbox = windowAnimationCheckbox
```

After the line `repeatedMaximizeRestoresPreviousCheckbox?.state = Defaults.repeatedMaximizeRestoresPrevious.enabled ? .on : .off` add:

```swift
        windowAnimationCheckbox?.state = Defaults.windowAnimation.enabled ? .on : .off
```

- [ ] **Step 3: Register the strings**

Build the app; the string catalog sync adds the new keys to `Rectangle/mul.lproj/Main.xcstrings`:

```bash
xcodebuild build -project Rectangle.xcodeproj -scheme Rectangle -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "error:|\*\* BUILD"
git diff --stat Rectangle/mul.lproj/Main.xcstrings
```

Expected: build succeeds and the diff shows additions. Verify all six keys are present:

```bash
grep -c '"Animate window movement" : {\|"Windows glide and scale into place\|"Screen Recording permission is needed\|"Rectangle takes a snapshot of a window\|"Open System Settings" : {\|"Later" : {' Rectangle/mul.lproj/Main.xcstrings
```

Expected: `6`. If the build did not add them, insert each missing key by hand with this script (keys are kept in byte order like the rest of the file):

```bash
python3 - <<'EOF'
import re
p = "Rectangle/mul.lproj/Main.xcstrings"
s = open(p).read()
keys = [
    "Animate window movement",
    "Windows glide and scale into place, like Windows 11. Needs the Screen Recording permission; windows move instantly without it or when Reduce Motion is on.",
    "Screen Recording permission is needed to animate window movement",
    "Rectangle takes a snapshot of a window to animate it. If macOS just asked, choose Allow. Otherwise enable Rectangle under Privacy & Security > Screen Recording. Quit and reopen Rectangle afterwards. Until then, windows move instantly.",
    "Open System Settings",
    "Later",
]
for key in keys:
    if f'"{key}" : {{' in s:
        continue
    entry = f'    "{key}" : {{\n\n    }},\n'
    positions = [m.start() for m in re.finditer(r'^    "((?:[^"\\]|\\.)*)" : \{', s, re.M)]
    inserted = False
    for pos in positions:
        existing = re.match(r'^    "((?:[^"\\]|\\.)*)" : \{', s[pos:], re.M).group(1)
        if existing > key:
            s = s[:pos] + entry + s[pos:]
            inserted = True
            break
    assert inserted, key
open(p, "w").write(s)
print("done")
EOF
```

- [ ] **Step 4: Check the checkbox works**

Relaunch the Debug build:

```bash
pkill -x Rectangle; open "$(ls -d ~/Library/Developer/Xcode/DerivedData/Rectangle-*/Build/Products/Debug/Rectangle.app | head -1)"
```

Open Settings > General > Extras. Expected: "Animate window movement" is the last checkbox, its state matches the `windowAnimation` default, and turning it on either does nothing (permission already granted) or shows the alert with "Open System Settings" and "Later". Turn it off and on again to confirm the state persists across reopening the popover.

- [ ] **Step 5: Commit**

```bash
git add Rectangle/WindowAnimation/ScreenRecordingAuthorization.swift Rectangle/PrefsWindow/SettingsViewController.swift Rectangle/mul.lproj/Main.xcstrings
git commit -m "Add the Animate window movement setting and permission flow

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Manual verification pass

No code unless a check fails. Fixes discovered here get their own commits with the failing scenario in the message.

**Files:**
- Read: the built Debug app.

- [ ] **Step 1: Prepare**

Rebuild and relaunch the Debug app (Task 9 Step 4 commands). Ensure Screen Recording is granted (re-add the app in System Settings if a rebuild invalidated it) and the checkbox is on. Open Rectangle's log window (menu bar icon > Settings, then the "View Logging" link) to see `Window animation:` lines if something is skipped.

- [ ] **Step 2: Native app**

With a Finder window: Left Half, Right Half, Maximize, Restore, Center, Larger, Smaller. Expected for each: no jump before the glide; the ghost scales smoothly into the exact final frame; the overlay fades out so the real window's re-rendered content replaces the stretched snapshot; the Finder window stays focused and responds to clicks immediately after.

- [ ] **Step 3: Chromium**

Same set with a Chrome / Electron window. Expected: identical smoothness (the ghost is independent of the app's redraw). The cross-fade at the end may reveal the app still relaying out; that is acceptable.

- [ ] **Step 4: Cross-display** (skip if only one display)

Next Display / Previous Display with a window. Expected: the overlay spans both displays, the ghost glides across, and the final frame on the destination display is correct even when the size is applied in Rectangle's retry.

- [ ] **Step 5: Cooperative corner resize**

Enable the cooperative corner resize setting, tile two windows side by side with Left Half / Right Half, then cycle Top Left on the left one so the right window also moves. Expected: both windows glide together, no duplicate of the neighbour at its old spot.

- [ ] **Step 6: Drag-to-snap**

Drag a window to the left screen edge and release. Expected: the footprint disappears, then the window glides into the half. Drag it back out. Expected: the unsnap-restore resizes instantly under the cursor with no overlay (deliberately not animated).

- [ ] **Step 7: Rapid repeats and multi-window**

Hold the Left Half shortcut so it cycles sizes quickly. Expected: each press supersedes the previous animation; no queued ghosts, no stuck overlay. Run Tile All and Cascade All from the menu. Expected: every window glides.

- [ ] **Step 8: Disable paths**

Turn on System Settings > Accessibility > Display > Reduce motion. Expected: moves are instant, no overlay. Turn it off. Turn the checkbox off. Expected: instant moves. Turn it back on.

- [ ] **Step 9: Focus and click-through**

While an animation is running (use `defaults write com.knollsoft.Rectangle windowAnimationDuration -float 1` and relaunch to make it slow), click another window during the glide. Expected: the click reaches that window; the overlay never becomes key. Reset the duration:

```bash
defaults delete com.knollsoft.Rectangle windowAnimationDuration
```

- [ ] **Step 10: Record what you saw**

Append a short "Verified on <date>, macOS <version>" note listing the eight scenarios and their outcome to the end of `docs/superpowers/specs/2026-09-11-window-move-animation-design.md`, then commit:

```bash
git add docs/superpowers/specs/2026-09-11-window-move-animation-design.md
git commit -m "Record manual verification of the window move animation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
