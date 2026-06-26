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
