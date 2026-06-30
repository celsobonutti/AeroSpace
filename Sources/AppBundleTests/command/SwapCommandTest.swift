@testable import AppBundle
import Common
import XCTest

@MainActor
final class SwapCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSwap_swapWindows_Directional() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("swap right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(3), .window(2)]),
                               .window(1)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(1), .window(2)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(2), .window(1)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(1), .window(2)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)
    }

    func testSwap_swapWindows_DfsRelative() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("swap dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(2), .window(1)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(2), .window(3)]),
                               .window(1)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(2), .window(1)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription,
                     .h_tiles([.v_tiles([.window(1), .window(2)]),
                               .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)
    }

    func testSwap_DirectionalWrapping() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("swap --wrap-around left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(3), .window(2), .window(1)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap --wrap-around right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)
    }

    func testSwap_DfsRelativeWrapping() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("swap --wrap-around dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(3), .window(2), .window(1)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)

        await parseCommand("swap --wrap-around dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 1)
    }

    func testSwap_moveMouse_followsSwappedWindow() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        let w1 = root.allLeafWindowsRecursive.first { $0.windowId == 1 }.orDie()
        let w2 = root.allLeafWindowsRecursive.first { $0.windowId == 2 }.orDie()
        // Tests don't run real layout, so seed the on-screen rects.
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w2Rect = Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 100)
        w2.lastAppliedLayoutPhysicalRect = w2Rect
        lastRequestedMouseMoveForTests = nil

        await parseCommand("swap dfs-next --move-mouse").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // Focus stays on window 1 (no --swap-focus); it now sits in window 2's old slot,
        // so the cursor should recenter there.
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(lastRequestedMouseMoveForTests, w2Rect.center)
    }

    func testSwap_withoutMoveMouseFlag_doesNotMoveMouse() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        root.allLeafWindowsRecursive.first { $0.windowId == 1 }?.lastAppliedLayoutPhysicalRect =
            Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        root.allLeafWindowsRecursive.first { $0.windowId == 2 }?.lastAppliedLayoutPhysicalRect =
            Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 100)
        lastRequestedMouseMoveForTests = nil

        await parseCommand("swap dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(lastRequestedMouseMoveForTests, nil)
    }

    func testSwap_moveMouse_withSwapFocus_followsFocus() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
        }
        let w1 = root.allLeafWindowsRecursive.first { $0.windowId == 1 }.orDie()
        let w2 = root.allLeafWindowsRecursive.first { $0.windowId == 2 }.orDie()
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w2Rect = Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 100)
        w2.lastAppliedLayoutPhysicalRect = w2Rect
        lastRequestedMouseMoveForTests = nil

        // Focused window 2 swaps with previous window 1; --swap-focus moves focus to window 1,
        // which now occupies window 2's old slot, so the cursor recenters there.
        await parseCommand("swap dfs-prev --swap-focus --move-mouse").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(lastRequestedMouseMoveForTests, w2Rect.center)
    }

    func testSwap_masterInTall_isCleanNoop() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        for id: UInt32 in [1, 2, 3] {
            workspace.allLeafWindowsRecursive.first { $0.windowId == id }?.lastAppliedLayoutPhysicalRect =
                Rect(topLeftX: CGFloat(id) * 100, topLeftY: 0, width: 100, height: 100)
        }
        lastRequestedMouseMoveForTests = nil

        // Master (1) is focused. dfs-next targets the stack top (2): a master-involved (boundary) swap.
        // The pinned-master reflow would revert it, so it must be a clean no-op — no mouse move, no focus change.
        await parseCommand("swap dfs-next --wrap-around --move-mouse").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(workspace.rootTilingContainer.layoutDescription,
                     .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
        assertEquals(lastRequestedMouseMoveForTests, nil)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testSwap_stackTopToMasterInTall_isCleanNoop() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        for id: UInt32 in [1, 2, 3] {
            workspace.allLeafWindowsRecursive.first { $0.windowId == id }?.lastAppliedLayoutPhysicalRect =
                Rect(topLeftX: CGFloat(id) * 100, topLeftY: 0, width: 100, height: 100)
        }
        // Focus the stack top (2); dfs-prev targets the master (1): also a boundary swap → no-op.
        assertEquals(workspace.allLeafWindowsRecursive.first { $0.windowId == 2 }?.focusWindow(), true)
        lastRequestedMouseMoveForTests = nil

        await parseCommand("swap dfs-prev --wrap-around --move-mouse").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(workspace.rootTilingContainer.layoutDescription,
                     .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
        assertEquals(lastRequestedMouseMoveForTests, nil)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testSwap_betweenStackWindowsInTall_stillWorks() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // master = 2 (it was focused on entry). stack = [1, 3]. Focus the stack top.
        assertEquals(workspace.masterWindow?.windowId, 2)
        let stackTop = (workspace.rootTilingContainer.children[1] as! TilingContainer).children.first as? Window
        assertEquals(stackTop?.focusWindow(), true)

        // Swapping two stack windows is NOT a boundary swap; it must still reorder the stack.
        await parseCommand("swap dfs-next --wrap-around").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let stackIds = (workspace.rootTilingContainer.children[1] as! TilingContainer)
            .children.compactMap { ($0 as? Window)?.windowId }
        assertEquals(stackIds, [3, 1])
        assertEquals(workspace.masterWindow?.windowId, 2)
    }

    func testSwap_SwapFocus() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("swap --swap-focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(3), .window(2)]))
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(root.mostRecentWindowRecursive?.windowId, 3)
    }
}
