# Window move animation (Windows 11 style) — design

Date: 2026-09-11
Status: approved in discussion, awaiting spec review

## Goal

When Rectangle moves or resizes a window, show a short animation of the
window scaling and sliding from its old frame to its new one, in the style
of Windows 11 snap animations and the macOS zoom effect. Today every move is
instant because the Accessibility (AX) API only lets us set a window's
position and size; it has no notion of animation and no third party can ask
WindowServer to animate another app's window.

The feature is opt-in (a checkbox, off by default) and requires the Screen
Recording permission.

## Non-goals

- Animating windows Rectangle did not move (e.g. a user dragging a window).
- Private SkyLight/CoreGraphics APIs. yabai gets a nicer effect this way but
  needs System Integrity Protection partially disabled.
- Stepping the AX frame over time (Loop's approach). It stutters with slow
  redrawing apps such as Electron and browsers and cannot fade. Not built,
  not planned as a fallback.

## Approach: snapshot ghost overlay, wrapped around the existing move

The real window still moves instantly through the existing code path. The
animation is an illusion painted by a Rectangle-owned overlay window:

1. **Begin** — before the first AX call of an action, capture an image of
   each window about to move and remember its current frame. Capture a
   backdrop image of the screen region involved, with every animated window
   excluded by window ID. Order a borderless, non-activating, click-through
   overlay window on screen covering that region. It shows the backdrop with
   each window's snapshot ("ghost") drawn on top at its old frame. Because the
   overlay is up first, the real windows can jump underneath unseen.
2. **Move** — the existing code runs untouched: mover chain, edge alignment,
   best-effort fitting, cross-display retries, cooperative corner resize.
3. **End** — read each window's actual final frame from AX. Ghosts whose
   window did not move are dropped. Each remaining ghost animates from its
   old frame to its final frame with a decelerating ease over
   `windowAnimationDuration` seconds (default 0.22). The overlay's alpha
   fades to zero over the last ~35% of that time so the stretched snapshot
   cross-fades into the freshly rendered real window. The overlay is then
   ordered out.

Why a transaction and not a change inside `AccessibilityElement.setFrame`:
the mover chain calls `setFrame` up to three times per action
(`StandardWindowMover`, `EdgeAlignmentWindowMover`, `BestEffortWindowMover`)
and cross-display moves retry, once synchronously and once after 25 ms.
Animating each call would produce several small hops. A transaction sees only
the initial and final frames.

### Windows that join mid-transaction

The cooperative corner cleanup pass (`applyCooperativeCornerCleanupIfNeeded`)
computes neighbour adjustments after the focused window has moved. The
transaction supports `include(element)` at that point: capture the window
(still at its old frame), add its ID to the exclusion set, and re-capture the
backdrop. Every capture taken after the overlay is on screen also excludes the
overlay's own window number.

### Overlapping transactions

A new transaction starting while a previous animation is still running
finishes the previous one instantly (overlay removed, no animation). Cycling
sizes quickly therefore never queues animations. One overlay window instance
is reused.

## Components

All new code lives in `Rectangle/WindowAnimation/`.

### `WindowAnimator` (`WindowAnimator.swift`)

Singleton owning the transaction lifecycle.

- `func begin(windows: [AccessibilityElement]) -> WindowMoveTransaction?`
  Returns nil (and does nothing) when animation is disabled or any
  precondition fails; callers then behave exactly as today.
- `WindowMoveTransaction.include(_ element: AccessibilityElement)` for late
  joiners.
- `WindowMoveTransaction.end()` reads final frames and starts the animation.
  `end()` is idempotent so every exit path can call it safely.
- `func perform(windows:, _ body: () -> Void)` convenience for the simple
  call sites: begin, run body, end.

Animation is skipped (begin returns nil) when:

- `Defaults.windowAnimation` is off.
- `CGPreflightScreenCaptureAccess()` is false.
- `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true.
- A capture fails or yields an empty image.
- The set of windows is empty or every window's frame is null.

At `end()`, if no window's frame changed, the overlay is removed without
animating.

### `WindowSnapshot` (`WindowSnapshot.swift`)

Image capture, isolated so it can later be swapped for ScreenCaptureKit.

- Window image: `CGWindowListCreateImage(.null, .optionIncludingWindow, id,
  [.boundsIgnoreFraming, .bestResolution])` — the window's own pixels,
  without its shadow, corners transparent.
- Backdrop: build the on-screen window list from `CGWindowListCopyWindowInfo`
  (`.optionOnScreenOnly`), drop the animated IDs and the overlay's ID, and
  pass the rest to `CGWindowListCreateImageFromArray(rect, ids,
  [.bestResolution])`. This includes the desktop, menu bar, and windows above
  the moved one; ghosts draw over them for the duration of the animation,
  which is an accepted inaccuracy.
- `CGWindowListCreateImage` is deprecated since macOS 14 but still functional
  with Screen Recording permission. The deployment target is 10.15, which
  rules out ScreenCaptureKit as the only path anyway.

### `GhostOverlayWindow` (`GhostOverlayWindow.swift`)

An `NSPanel` subclass:

- borderless, `nonactivatingPanel`, `ignoresMouseEvents = true`,
  `hasShadow = false`, `isOpaque = false`, `isReleasedWhenClosed = false`.
- `level = .floating` (above normal windows, below the menu bar and Dock).
- `collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]`.
- Layer-backed content view. One backdrop `CALayer` with the backdrop image,
  and one `CALayer` per ghost with `contentsGravity = .resize`, the window
  image as contents, and a soft shadow (opacity ~0.35, radius ~18, offset
  ~(0, -8)) so the ghost does not look flat against the backdrop.
- `contentsScale` is the larger backing scale factor of the displays the
  overlay spans.
- Animation: `CABasicAnimation` on `bounds` and `position` per ghost, timing
  function cubic-bezier(0.1, 0.9, 0.2, 1) (a strong ease-out, close to the
  Windows 11 decelerate curve). Overlay `alphaValue` animated to 0 starting at
  65% of the duration, ending at 100%. Completion orders the overlay out and
  clears the layers.
- `displayIfNeeded()` and `CATransaction.flush()` are called after
  `orderFront` at begin so the overlay is committed to WindowServer before
  the AX moves start.

### `WindowAnimationGeometry` (`WindowAnimationGeometry.swift`)

Pure functions, no AppKit windows, fully unit-tested:

- `overlayRect(for oldFrames: [CGRect], newFrames: [CGRect], shadowInset:
  CGFloat) -> CGRect` — union in AppKit (bottom-left) coordinates, padded for
  the ghost shadow.
- `ghostFrame(_ axFrame: CGRect, inOverlay overlayRect: CGRect) -> CGRect` —
  converts an AX (top-left origin) frame via `screenFlipped` into
  overlay-local coordinates.
- `movedWindows(old: [CGWindowID: CGRect], final: [CGWindowID: CGRect]) ->
  [CGWindowID]` — IDs whose frame changed.
- `fadeStartFraction` and duration clamping (0.05 … 1.0 s).
- `shouldAnimate(enabled: Bool, hasPermission: Bool, reduceMotion: Bool) ->
  Bool`.

### Settings

- `Defaults.windowAnimation = BoolDefault(key: "windowAnimation")` (off).
- `Defaults.windowAnimationDuration = FloatDefault(key:
  "windowAnimationDuration", defaultValue: 0.22)` — hidden, terminal only.
- Both registered in the `Defaults.array` list like the other defaults.
- Checkbox "Animate window movement" in the Extras popover of the General
  tab, added programmatically in `SettingsViewController` the same way the
  "Repeated Maximize restores…" checkbox was (title and tooltip registered
  in `Main.xcstrings`). Tooltip explains that Screen Recording permission is
  required.
- `TerminalCommands.md` gains a section for both keys.

### Permission flow

Turning the checkbox on:

1. If `CGPreflightScreenCaptureAccess()` is true, done.
2. Otherwise call `CGRequestScreenCaptureAccess()`. macOS shows its prompt
   the first time; on later calls it returns false without a prompt.
3. If still not granted, show an alert: animation needs Screen Recording,
   with a button that opens
   `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`,
   and a note that Rectangle must be relaunched after granting. The checkbox
   stays on; the animator's per-action preflight keeps moves instant until
   permission is present.

No usage-description key is required in `Info.plist` for Screen Recording.
Users on macOS 15+ will see the periodic system reminder that Rectangle can
record the screen; this is documented in the terminal commands section.

## Call sites wrapped in a transaction

| Call site | Windows in the transaction |
|---|---|
| `WindowManager.execute` — main path, after all early no-op returns, before `apply`/`applyCooperativeCornerResize` | focused window plus the cooperative plan's adjustment elements, if any |
| `WindowManager.execute` — cooperative cleanup adjustments (`apply(_ adjustments:)`) | `include` each adjustment element before its `setFrame` |
| `WindowManager.execute` — Restore branch | focused window |
| `WindowManager.execute` — cross-display 25 ms retry | same transaction, ended in `postProcess` |
| `SnappingManager.unsnapRestore` | dragged window |
| `MultiWindowManager` (tile / cascade) and `ReverseAllManager` | every window they touch |
| `TodoManager` reflow | every window it touches |

`execute`'s transaction is ended in `postProcess`, which every successful
path reaches, and in the early returns that occur after begin (there are none
today; the guard exists for future edits). Drag-to-snap release, menu, URL,
and title-bar sources all reach `execute`, so they are covered by the first
row.

## Error handling

- Any capture failure aborts the transaction before the overlay is shown; the
  move proceeds instantly. Failures are logged through `Logger.log`.
- If the overlay cannot be created, same fallback.
- `end()` runs on the main thread; if called off-main it dispatches to main.
- The overlay is torn down on `NSApplication.willTerminate` and when screens
  change (`NSApplication.didChangeScreenParametersNotification`) to avoid a
  stale ghost after a display reconfiguration.

## Testing

### Unit tests (`RectangleTests/WindowAnimationTests.swift`)

- Overlay rect union, including a cross-display case and the shadow inset.
- AX-to-overlay frame conversion round-trips for windows on the main and a
  secondary display.
- `movedWindows` drops unchanged windows and keeps moved ones.
- `shouldAnimate` truth table over setting, permission, reduce motion.
- Duration clamping.
- Transaction behaviour with test doubles. The animator depends on two
  small protocols so the tests need no real windows: a `WindowFrameSource`
  (window ID plus current frame, which `AccessibilityElement` conforms to) and
  a `WindowSnapshotProvider` (the capture calls). Tests inject fakes and
  check: begin returns nil when disabled; `end()` is idempotent; a second
  `begin` finishes the first transaction; unchanged windows get no ghost.

### Throwaway probe (first implementation task)

Before building on the capture path, confirm on this machine (macOS 26.6):

1. `CGWindowListCreateImage` returns non-empty pixels for another app's
   window once Screen Recording is granted.
2. Ordering the overlay front, then setting the AX frame, hides the jump. If
   a frame of the jump is still visible, switch to ordering the overlay front
   one display refresh earlier via `CATransaction.flush()` plus a run-loop
   spin, and if that still fails, document the residual flash and proceed.

The probe code is not kept.

### Manual verification

Build, enable the checkbox, grant permission, relaunch, and check:

- A native app (Finder) — left half, right half, maximize, restore.
- A Chromium window — same, watching for the cross-fade at the end.
- A cross-display move with the "next display" action.
- A cooperative corner resize with two windows.
- Drag-to-snap release and unsnap restore.
- Rapid repeated shortcuts (cycle sizes) — no queued ghosts.
- Reduce Motion on — moves are instant.
