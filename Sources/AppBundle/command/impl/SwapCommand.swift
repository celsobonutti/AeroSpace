import AppKit
import Common

struct SwapCommand: Command {
    let args: SwapCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else {
            return .fail
        }

        guard let currentWindow = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }

        let targetWindow: Window?
        switch args.target.val {
            case .direction(let direction):
                switch currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    case let (parent, ownIndex)?:
                        targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil where args.wrapAround:
                        targetWindow = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil:
                        return .fail
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return .fail
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    if !args.wrapAround {
                        return .fail
                    }
                    targetIndex = (targetIndex + windows.count) % windows.count
                }
                targetWindow = windows[targetIndex]
        }

        guard let targetWindow else {
            return .fail
        }

        // Capture rects before the swap: the new layout isn't applied until the session
        // ends, so each window's lastAppliedLayoutPhysicalRect still holds its old slot.
        // After the swap, the focused window occupies the OTHER window's old slot.
        let currentRect = currentWindow.lastAppliedLayoutPhysicalRect
        let targetRect = targetWindow.lastAppliedLayoutPhysicalRect

        swapWindows(mruDominant: currentWindow, targetWindow)

        if args.moveMouse {
            let focusedNewRect = args.swapFocus ? currentRect : targetRect
            if let focusedNewRect {
                postMouseMove(to: focusedNewRect.center)
            }
        }

        if args.swapFocus {
            return .from(bool: targetWindow.focusWindow())
        }
        return .succ
    }
}
