@testable import AppBundle
import Common
import XCTest

@MainActor
final class PromoteCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testPromoteFocusedStackWindow() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.masterWindow?.windowId, 1)

        // Focus a stack window and promote it.
        assertEquals(workspace.allLeafWindowsRecursive.first { $0.windowId == 3 }?.focusWindow(), true)
        await parseCommand("promote").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(workspace.masterWindow?.windowId, 3)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(3),
            .v_tiles([.window(2), .window(1)]),
        ]))
    }

    func testPromoteRecentersMouseOnMasterSlot() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // Tests don't run real layout, so seed the master slot's on-screen rect.
        let masterRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 200)
        workspace.masterWindow?.lastAppliedLayoutPhysicalRect = masterRect
        lastRequestedMouseMoveForTests = nil

        // Promote a stack window: the mouse should recenter on the master slot.
        assertEquals(workspace.allLeafWindowsRecursive.first { $0.windowId == 3 }?.focusWindow(), true)
        await parseCommand("promote").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(lastRequestedMouseMoveForTests, masterRect.center)
    }

    func testPromoteMaster_isNoop() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let result = await parseCommand("promote --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(workspace.masterWindow?.windowId, 1)
    }
}
