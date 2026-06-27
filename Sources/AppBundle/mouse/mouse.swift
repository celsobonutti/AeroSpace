import AppKit
import Common

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow(.cancellable) == window }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }

/// Records the last requested mouse-move target so unit tests can observe mouse movement
/// without posting real OS events. Same spirit as `appForTests`.
@MainActor var lastRequestedMouseMoveForTests: CGPoint? = nil

/// Moves the system cursor to `point`. Returns `false` if the event couldn't be created.
/// No real event is posted under unit tests.
@MainActor
@discardableResult
func postMouseMove(to point: CGPoint) -> Bool {
    lastRequestedMouseMoveForTests = point
    if isUnitTest { return true }
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: CGEventType.mouseMoved,
        mouseCursorPosition: point,
        mouseButton: CGMouseButton.left,
    ) else {
        return false
    }
    event.post(tap: CGEventTapLocation.cghidEventTap)
    return true
}
