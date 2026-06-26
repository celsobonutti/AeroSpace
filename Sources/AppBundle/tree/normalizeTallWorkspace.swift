import AppKit
import Common

extension Workspace {
    /// Reshapes a tall workspace's tree into the canonical master-stack form:
    /// `rootTilingContainer(.h/.tiles) = [masterWindow, stackContainer(.v/.tiles, rest...)]`.
    /// Idempotent. No-op unless `layoutMode == .tall`.
    @MainActor
    func normalizeTallWorkspace() {
        guard layoutMode == .tall else { return }
        let root = rootTilingContainer
        let windows = root.allLeafWindowsRecursive // DFS order

        // Resolve the master: keep the pinned one if still present, else the first window.
        let master: Window? = masterWindow.flatMap { tracked in
            windows.first { $0 === tracked }
        } ?? windows.first
        masterWindow = master

        guard let master else { return } // Empty workspace: leave root empty.
        let stackWindows = windows.filter { $0 !== master }

        // Capture (or seed) the master/stack split ratio before tearing down.
        let canonical = root.children.count == 2
            && root.children[0] is Window
            && root.children[1] is TilingContainer
        let masterWeight: CGFloat
        let stackWeight: CGFloat
        if canonical {
            masterWeight = root.children[0].getWeight(.h)
            stackWeight = root.children[1].getWeight(.h)
        } else {
            let totalWidth = workspaceMonitor.visibleRectPaddedByOuterGaps.width
            let r = CGFloat(config.tallMasterRatioPercent).div(100) ?? 0.5
            masterWeight = r * totalWidth
            stackWeight = (1 - r) * totalWidth
        }

        // Root must be horizontal tiles.
        root.layout = .tiles
        root.setOrientationForTall(.h)

        // Detach every window so we can rebind into the canonical structure.
        for window in windows { window.unbindFromParent() }
        // Remove any leftover containers under root (e.g. from join-with/split).
        for child in root.children { child.unbindFromParent() }

        master.bind(to: root, adaptiveWeight: masterWeight, index: 0)

        if !stackWindows.isEmpty {
            let stack = TilingContainer.newVTiles(parent: root, adaptiveWeight: stackWeight, index: INDEX_BIND_LAST)
            stack.setOrientationForTall(.v)
            for window in stackWindows {
                window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
    }
}
