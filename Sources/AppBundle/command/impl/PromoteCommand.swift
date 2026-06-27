import AppKit
import Common

struct PromoteCommand: Command {
    let args: PromoteCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        let workspace = target.workspace
        guard workspace.layoutMode == .tall else {
            return .fail(io.err("promote is only available in 'tall' workspaces"))
        }
        guard let master = workspace.masterWindow, master !== window else {
            // Already the master: nothing to promote.
            switch args.failIfNoop {
                case true: return .fail
                case false: return .succ
            }
        }

        // The promoted window takes over the master slot, so recenter the mouse there.
        // Capture the master slot's rect before the swap: the new layout isn't applied
        // yet, so the promoted window's own `lastAppliedLayoutPhysicalRect` is still its
        // old stack position. The outgoing master's rect IS the master slot.
        let masterSlotRect = master.lastAppliedLayoutPhysicalRect

        swapWindows(mruDominant: window, master)
        workspace.masterWindow = window
        workspace.normalizeTallWorkspace()

        if let masterSlotRect {
            postMouseMove(to: masterSlotRect.center)
        }
        return .succ
    }
}
