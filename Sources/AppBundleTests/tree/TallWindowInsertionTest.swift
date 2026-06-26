@testable import AppBundle
import Common
import XCTest

@MainActor
final class TallWindowInsertionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testNewWindowGoesToStackTop() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.layoutMode = .tall
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        workspace.normalizeTallWorkspace()
        // Canonical: [1, vstack[2, 3]]

        // A brand-new tiling window relayout-bound into the workspace must land at stack top.
        let newWindow = TestWindow.new(id: 99, parent: workspace.rootTilingContainer)
        try await newWindow.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)

        let stack = workspace.rootTilingContainer.children[1] as! TilingContainer
        assertEquals((stack.children.first as? Window)?.windowId, 99)
    }
}
