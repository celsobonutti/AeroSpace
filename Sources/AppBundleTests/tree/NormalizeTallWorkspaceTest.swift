@testable import AppBundle
import Common
import XCTest

@MainActor
final class NormalizeTallWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTwoWindows_buildsMasterPlusStack() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2)]),
        ]))
        assertEquals(workspace.masterWindow?.windowId, 1)
    }

    func testThreeWindows_stacksNonMasterVertically() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2), .window(3)]),
        ]))
    }

    func testSingleWindow_isMasterOnly() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        assertEquals(workspace.masterWindow?.windowId, 1)
    }

    func testMasterIsPinnedByIdentity() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        // Pin window 2 as master, then reflow again.
        workspace.masterWindow = workspace.allLeafWindowsRecursive.first { $0.windowId == 2 }
        workspace.normalizeTallWorkspace()
        assertEquals(root.layoutDescription, .h_tiles([
            .window(2),
            .v_tiles([.window(1), .window(3)]),
        ]))
    }

    func testClosedMaster_promotesStackTop() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        assertEquals(workspace.masterWindow?.windowId, 1)
        // Simulate the master closing (unbind from tree).
        workspace.allLeafWindowsRecursive.first { $0.windowId == 1 }?.unbindFromParent()
        workspace.normalizeTallWorkspace()
        assertEquals(root.layoutDescription, .h_tiles([
            .window(2),
            .v_tiles([.window(3)]),
        ]))
        assertEquals(workspace.masterWindow?.windowId, 2)
    }

    func testSeedsMasterRatioFromConfig() {
        config.tallMasterRatioPercent = 70
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        let master = root.children[0]
        let stack = root.children[1]
        let ratio = master.getWeight(.h) / (master.getWeight(.h) + stack.getWeight(.h))
        assertEquals((ratio * 100).rounded(), 70)
    }

    func testNewWorkspaceSeedsLayoutModeFromConfig() {
        config.defaultWorkspaceLayout = .tall
        let workspace = Workspace.get(byName: "freshly-created-tall-ws")
        assertEquals(workspace.layoutMode, .tall)
    }

    func testNormalizeContainers_dispatchesToTall() {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        // Generic normalize entry point should produce the canonical tall tree.
        workspace.normalizeContainers()
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2), .window(3)]),
        ]))
    }
}
