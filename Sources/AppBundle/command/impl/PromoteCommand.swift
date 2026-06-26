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

        swapWindows(mruDominant: window, master)
        workspace.masterWindow = window
        workspace.normalizeTallWorkspace()
        return .succ
    }
}
