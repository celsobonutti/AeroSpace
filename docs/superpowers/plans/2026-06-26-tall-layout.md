# Tall Workspace Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dynamic master-stack ("tall") workspace layout — one master window in a left column, all other windows stacked vertically in a right column — that auto-reflows as windows are added, removed, and reordered.

**Architecture:** `tall` is a per-workspace *mode*, not a new rendering algorithm. When a workspace is in tall mode, an idempotent reflow pass (`normalizeTallWorkspace`) keeps its tree in the canonical shape `rootTilingContainer(.h/.tiles) = [masterWindow, stackContainer(.v/.tiles)]`. The existing `tiles` layout algorithm renders it; existing directional `focus`/`move`/`resize` operate on it unchanged. The master is identity-tracked and pinned; it changes only via the new `promote` command.

**Tech Stack:** Swift, macOS, Swift Package Manager. Tests via XCTest in `Sources/AppBundleTests`. Build: `./build-debug.sh` (or `swift build`); test: `swift test`.

## Global Constraints

- Master count is exactly **one** in v1. No multi-master.
- `tall` is **workspace-scoped**. All tiling windows in the workspace participate.
- The master is **identity-tracked and pinned**; changed only by `promote`. Generic `move`/`swap` never silently change the master.
- New windows are inserted at the **top of the stack**; the master is never displaced.
- `OrderedJson` (the config value type) supports only int/string/bool — **no floats**. `tall-master-ratio` is therefore an **integer percentage 1–99** (default `50`).
- Do not break the existing manual-tiling behavior: every change is gated behind `workspace.layoutMode == .tall`.
- Tests disable normalization flags (`setUpWorkspacesForTests` sets `enableNormalizationFlattenContainers = false`, `enableNormalizationOppositeOrientationForNestedContainers = false`, `defaultRootContainerOrientation = .horizontal`).

---

### Task 1: Data model + reflow pass

**Files:**
- Modify: `Sources/AppBundle/config/Config.swift` (add `WorkspaceLayout` enum + two `Config` fields)
- Modify: `Sources/AppBundle/tree/Workspace.swift` (add `layoutMode` + `masterWindow` state)
- Modify: `Sources/AppBundle/tree/TilingContainer.swift` (add a no-cascade orientation setter)
- Create: `Sources/AppBundle/tree/normalizeTallWorkspace.swift`
- Create test: `Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift`

**Interfaces:**
- Produces:
  - `enum WorkspaceLayout: String { case tiling, tall }` (in `Config.swift`)
  - `Config.defaultWorkspaceLayout: WorkspaceLayout` (default `.tiling`)
  - `Config.tallMasterRatioPercent: Int` (default `50`)
  - `Workspace.layoutMode: WorkspaceLayout` (default `.tiling`, settable)
  - `Workspace.masterWindow: Window?` (weak, settable)
  - `TilingContainer.setOrientationForTall(_ orientation: Orientation)` — sets `_orientation` directly, no parent cascade
  - `Workspace.normalizeTallWorkspace()` — reshapes the tree into canonical tall form; no-op unless `layoutMode == .tall`

- [ ] **Step 1: Add the `WorkspaceLayout` enum and `Config` fields**

In `Sources/AppBundle/config/Config.swift`, add the enum next to `DefaultContainerOrientation` (bottom of file):

```swift
enum WorkspaceLayout: String {
    case tiling
    case tall
}
```

Inside `struct Config`, add two fields after `var defaultRootContainerOrientation: DefaultContainerOrientation = .auto`:

```swift
    var defaultWorkspaceLayout: WorkspaceLayout = .tiling
    var tallMasterRatioPercent: Int = 50
```

- [ ] **Step 2: Add mutable state to `Workspace`**

In `Sources/AppBundle/tree/Workspace.swift`, inside `final class Workspace`, after the line `fileprivate var assignedMonitorPoint: CGPoint? = nil` add:

```swift
    /// Workspace-level layout mode. `.tall` enables the dynamic master-stack layout.
    var layoutMode: WorkspaceLayout = .tiling
    /// The pinned master window when `layoutMode == .tall`. Tracked by identity; resolved/repaired by `normalizeTallWorkspace`.
    weak var masterWindow: Window?
```

- [ ] **Step 3: Add a no-cascade orientation setter to `TilingContainer`**

In `Sources/AppBundle/tree/TilingContainer.swift`, inside `extension TilingContainer` (after `changeOrientation`), add:

```swift
    /// Sets orientation directly without the opposite-orientation cascade that `changeOrientation` applies.
    /// Used by the tall reflow, which controls the whole tree shape explicitly.
    @MainActor
    func setOrientationForTall(_ targetOrientation: Orientation) {
        _orientation = targetOrientation
    }
```

(`_orientation` is `fileprivate`, so this method MUST live in `TilingContainer.swift`.)

- [ ] **Step 4: Write the failing test for the reflow pass**

Create `Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift`:

```swift
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
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `swift test --filter NormalizeTallWorkspaceTest`
Expected: FAIL — `normalizeTallWorkspace` does not exist (compile error).

- [ ] **Step 6: Implement `normalizeTallWorkspace`**

Create `Sources/AppBundle/tree/normalizeTallWorkspace.swift`:

```swift
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
```

Note: `CGFloat.div(_:)` is the codebase's safe-divide helper (returns `nil` on divide-by-zero); see its use in `layoutRecursive.swift`/`TreeNode.swift`.

- [ ] **Step 7: Run the test to verify it passes**

Run: `swift test --filter NormalizeTallWorkspaceTest`
Expected: PASS (all 6 tests).

- [ ] **Step 8: Commit**

```bash
git add Sources/AppBundle/config/Config.swift Sources/AppBundle/tree/Workspace.swift Sources/AppBundle/tree/TilingContainer.swift Sources/AppBundle/tree/normalizeTallWorkspace.swift Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift
git commit -m "Add tall workspace state and reflow pass

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Run the reflow in the refresh cycle

**Files:**
- Modify: `Sources/AppBundle/tree/normalizeContainers.swift`
- Modify test: `Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift`

**Interfaces:**
- Consumes: `Workspace.normalizeTallWorkspace()`, `Workspace.layoutMode` (Task 1).
- Produces: `Workspace.normalizeContainers()` now dispatches to `normalizeTallWorkspace()` for tall workspaces (skipping the flatten/opposite-orientation passes). This is invoked for every workspace each refresh via the private `normalizeContainers()` in `refresh.swift` (no change needed there).

- [ ] **Step 1: Write the failing test**

Append to `NormalizeTallWorkspaceTest`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter NormalizeTallWorkspaceTest/testNormalizeContainers_dispatchesToTall`
Expected: FAIL — `normalizeContainers()` runs the default flatten path, leaving a flat `.h_tiles([1,2,3])`.

- [ ] **Step 3: Add the dispatch branch**

In `Sources/AppBundle/tree/normalizeContainers.swift`, replace the body of `normalizeContainers()`:

```swift
extension Workspace {
    @MainActor func normalizeContainers() {
        if layoutMode == .tall {
            normalizeTallWorkspace()
            return
        }
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter NormalizeTallWorkspaceTest`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/tree/normalizeContainers.swift Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift
git commit -m "Dispatch normalizeContainers to tall reflow for tall workspaces

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `layout tall` command

**Files:**
- Modify: `Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift` (add `.tall` case + parse filter)
- Modify: `Sources/AppBundle/command/impl/LayoutCommand.swift` (workspace-aware matching + apply)
- Modify test: `Sources/AppBundleTests/command/LayoutCommandTest.swift`

**Interfaces:**
- Consumes: `Workspace.layoutMode`, `Workspace.masterWindow`, `Workspace.normalizeTallWorkspace()` (Task 1).
- Produces: `layout tall` sets `target.workspace.layoutMode = .tall`; selecting any non-tall layout description clears it back to `.tiling`. Toggle syntax `layout tall tiles` works.

- [ ] **Step 1: Add `.tall` to `LayoutDescription` and the parse filter**

In `Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift`, add `tall` to the enum:

```swift
    public enum LayoutDescription: String, CaseIterable, Equatable, Sendable {
        case accordion, tiles
        case horizontal, vertical
        case h_accordion, v_accordion, h_tiles, v_tiles
        case tiling, floating
        case tall
    }
```

In `parseLayoutCmdArgs`, the `--root` incompatibility filter has an exhaustive `switch` — add `.tall` to the allowed (`true`) group:

```swift
        .filter(layoutCommandRootFlagIncompatibilityMsg) { cmdArgs in
            !cmdArgs.root || cmdArgs.toggleBetween.val.allSatisfy {
                switch $0 {
                    case .floating, .tiling: false
                    case .accordion, .h_accordion, .h_tiles,
                         .horizontal, .tiles, .v_accordion, .v_tiles,
                         .vertical, .tall: true
                }
            }
        }
```

- [ ] **Step 2: Write failing tests**

Append to `LayoutCommandTest`:

```swift
    func testEnterTall_buildsMasterStack() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.layoutMode, .tall)
        assertEquals(workspace.masterWindow?.windowId, 1)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2), .window(3)]),
        ]))
    }

    func testToggleTallAndTiles() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        // tiling -> tall
        await parseCommand("layout tall tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.layoutMode, .tall)
        // tall -> tiling
        await parseCommand("layout tall tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.layoutMode, .tiling)
    }

    func testEnterTall_alreadyTall_isNoop() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        await parseCommand("layout tall").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let result = await parseCommand("layout tall --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(workspace.layoutMode, .tall)
    }
```

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --filter LayoutCommandTest`
Expected: FAIL — `.tall` is unhandled in `matchesDescription`/apply switch (compile error first).

- [ ] **Step 4: Make matching workspace-mode-aware**

In `Sources/AppBundle/command/impl/LayoutCommand.swift`, change the `matchesDescription` extension to take the workspace layout:

```swift
extension ConventionalWindowParentCases {
    fileprivate func matchesDescription(_ layout: LayoutCmdArgs.LayoutDescription, workspaceLayout: WorkspaceLayout) -> Bool {
        if workspaceLayout == .tall {
            return layout == .tall
        }
        return switch layout {
            case .tall:        false
            case .accordion:   tilingContainerOrNil?.layout == .accordion
            case .tiles:       tilingContainerOrNil?.layout == .tiles
            case .horizontal:  tilingContainerOrNil?.orientation == .h
            case .vertical:    tilingContainerOrNil?.orientation == .v
            case .h_accordion: tilingContainerOrNil.map { $0.layout == .accordion && $0.orientation == .h } == true
            case .v_accordion: tilingContainerOrNil.map { $0.layout == .accordion && $0.orientation == .v } == true
            case .h_tiles:     tilingContainerOrNil.map { $0.layout == .tiles && $0.orientation == .h } == true
            case .v_tiles:     tilingContainerOrNil.map { $0.layout == .tiles && $0.orientation == .v } == true
            case .tiling:      tilingContainerOrNil != nil
            case .floating:    floatingWindowsContainerOrNil != nil
        }
    }
}
```

- [ ] **Step 5: Update the two call sites and the apply switch**

In `run(...)`, update the toggle resolution and noop check to pass the workspace layout, and add the tall enter/exit logic. Replace the block from `let targetDescription = ...` through the end of the description `switch`:

```swift
        let workspaceLayout = target.workspace.layoutMode
        let targetDescription = args.toggleBetween.val.first(where: { !node.matchesDescription($0, workspaceLayout: workspaceLayout) })
            ?? args.toggleBetween.val.first.orDie()
        if node.matchesDescription(targetDescription, workspaceLayout: workspaceLayout) {
            switch args.failIfNoop {
                case true: return .fail
                case false:
                    let msg = "Already in the requested \(targetDescription.rawValue) mode. " +
                        "Tip: use --fail-if-noop to exit with non-zero exit code"
                    return .succ(io.err(msg))
            }
        }

        // `tall` is a workspace-level mode; all other descriptions imply leaving it.
        if targetDescription == .tall {
            let workspace = target.workspace
            workspace.layoutMode = .tall
            workspace.masterWindow = target.windowOrNil
                ?? workspace.masterWindow
                ?? workspace.rootTilingContainer.allLeafWindowsRecursive.first
            workspace.normalizeTallWorkspace()
            return .succ
        }
        if target.workspace.layoutMode == .tall {
            target.workspace.layoutMode = .tiling
        }

        switch targetDescription {
            case .tall:
                return .fail(io.err(bugPrompt())) // handled above
            case .h_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .h, node: node)
            case .v_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .v, node: node)
            case .h_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .h, node: node)
            case .v_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .v, node: node)
            case .accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: nil, node: node)
            case .tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: nil, node: node)
            case .horizontal:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .h, node: node)
            case .vertical:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .v, node: node)
            case .tiling:
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                switch node {
                    case .tilingContainer:
                        return .succ // Nothing to do
                    case .floatingWindowsContainer(let container):
                        window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                        guard let workspace = container.nodeWorkspace else { return .fail(io.err(bugPrompt())) }
                        do {
                            try await window.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
                        } catch {
                            return .fail(io.err(bugPrompt()))
                        }
                        return .succ
                }
            case .floating:
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                let workspace = target.workspace
                window.bindAsFloatingWindow(to: workspace)
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
                return .succ
        }
```

(Only the head of the method — `targetDescription`/noop/tall block — and the addition of the `case .tall` line are new; the remaining cases are unchanged from the original. They are repeated here in full because the surrounding `switch` must stay exhaustive.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter LayoutCommandTest`
Expected: PASS (existing tests + the 3 new tall tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift Sources/AppBundle/command/impl/LayoutCommand.swift Sources/AppBundleTests/command/LayoutCommandTest.swift
git commit -m "Add 'layout tall' workspace mode command

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `promote` command

**Files:**
- Modify: `Sources/Common/cmdArgs/cmdArgsManifest.swift` (`CmdKind` + `initSubcommands`)
- Create: `Sources/Common/cmdArgs/impl/PromoteCmdArgs.swift`
- Create: `Sources/AppBundle/command/impl/PromoteCommand.swift`
- Modify: `Sources/AppBundle/command/cmdManifest.swift` (`toCommand`)
- Create: `docs/aerospace-promote.adoc`
- Create test: `Sources/AppBundleTests/command/PromoteCommandTest.swift`

**Interfaces:**
- Consumes: `Workspace.masterWindow`, `Workspace.normalizeTallWorkspace()` (Task 1), `swapWindows(mruDominant:_:)` from `Sources/AppBundle/mouse/moveWithMouse.swift`.
- Produces: `promote` command (`CmdKind.promote`, rawValue `"promote"`). Swaps the focused window into the master slot and re-pins it.

- [ ] **Step 1: Register the command kind**

In `Sources/Common/cmdArgs/cmdArgsManifest.swift`, add to `CmdKind` (alphabetical, after `moveWorkspaceToMonitor` / before `reloadConfig`):

```swift
    case promote
```

And in `initSubcommands()`, add a case:

```swift
            case .promote:
                result[kind.rawValue] = SubCommandParser(PromoteCmdArgs.init)
```

- [ ] **Step 2: Create the args struct**

Create `Sources/Common/cmdArgs/impl/PromoteCmdArgs.swift`:

```swift
public struct PromoteCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .promote,
        help: promote_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [],
    )

    public var failIfNoop: Bool = false
}
```

- [ ] **Step 3: Map the kind to the command**

In `Sources/AppBundle/command/cmdManifest.swift`, add to the `switch` in `toCommand()`:

```swift
            case .promote:
                command = PromoteCommand(args: self as! PromoteCmdArgs)
```

- [ ] **Step 4: Add the help doc source**

Create `docs/aerospace-promote.adoc` (mirroring the structure of an existing single-command doc such as `docs/aerospace-swap.adoc` — open it first to copy the exact AsciiDoc header/attributes/synopsis block layout). The synopsis must define a `tag::synopsis[]` region:

```
// tag::synopsis[]
promote [-h|--help] [--window-id <window-id>] [--fail-if-noop]
// end::synopsis[]
```

Body: explain that `promote` swaps the focused window into the master slot of a `tall` workspace, demoting the previous master into the focused window's former stack position, and that it is a no-op in non-tall workspaces.

- [ ] **Step 5: Write the failing test**

Create `Sources/AppBundleTests/command/PromoteCommandTest.swift`:

```swift
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
```

(Expected stack order after promoting `3`: the swap exchanges window 3's slot with the master's, so the old master `1` lands in `3`'s former stack position. The stack was `[2, 3]`; after swap the stack is `[2, 1]`, then `3` is master.)

- [ ] **Step 6: Run it to verify it fails**

Run: `swift test --filter PromoteCommandTest`
Expected: FAIL — `promote_help_generated` / `PromoteCommand` undefined (compile error).

- [ ] **Step 7: Generate help text**

Run: `./generate.sh`
Expected: regenerates `Sources/Common/cmdHelpGenerated.swift` to include `promote_help_generated`, and updates `docs/commands.adoc`. (Open `generate.sh` first to confirm it has no prerequisites beyond the `.adoc` file; if it lists `promote` in a hardcoded command array somewhere, add it there too.)

- [ ] **Step 8: Implement the command**

Create `Sources/AppBundle/command/impl/PromoteCommand.swift`:

```swift
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
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `swift test --filter PromoteCommandTest`
Expected: PASS (both tests).

- [ ] **Step 10: Commit**

```bash
git add Sources/Common/cmdArgs/cmdArgsManifest.swift Sources/Common/cmdArgs/impl/PromoteCmdArgs.swift Sources/AppBundle/command/impl/PromoteCommand.swift Sources/AppBundle/command/cmdManifest.swift docs/aerospace-promote.adoc docs/commands.adoc Sources/Common/cmdHelpGenerated.swift Sources/AppBundleTests/command/PromoteCommandTest.swift
git commit -m "Add promote command (swap focused window into tall master slot)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: New windows insert at the stack top

**Files:**
- Modify: `Sources/AppBundle/tree/MacWindow.swift` (`unbindAndGetBindingDataForNewTilingWindow`)
- Create test: `Sources/AppBundleTests/tree/TallWindowInsertionTest.swift`

**Interfaces:**
- Consumes: `Workspace.layoutMode`, `Workspace.rootTilingContainer` (Task 1).
- Produces: in a tall workspace, a newly tiled window binds to the top (index 0) of the stack container, never displacing the master.

- [ ] **Step 1: Write the failing test**

Create `Sources/AppBundleTests/tree/TallWindowInsertionTest.swift`:

```swift
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
```

(`relayoutWindow(forceTile: true)` calls `unbindAndGetBindingDataForNewTilingWindow` then binds — the exact path a newly detected tiling window takes.)

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter TallWindowInsertionTest`
Expected: FAIL — the new window binds after the MRU window, not at stack top.

- [ ] **Step 3: Add the tall branch to the binding helper**

In `Sources/AppBundle/tree/MacWindow.swift`, update `unbindAndGetBindingDataForNewTilingWindow`:

```swift
@MainActor
private func unbindAndGetBindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent() // It's important to unbind to get correct data from below
    if workspace.layoutMode == .tall {
        let root = workspace.rootTilingContainer
        if let stack = root.children.filterIsInstance(of: TilingContainer.self).first {
            // Insert at the top of the existing stack column.
            return BindingData(parent: stack, adaptiveWeight: WEIGHT_AUTO, index: 0)
        } else {
            // 0 or 1 window so far: bind just after the master slot; the reflow canonicalizes.
            return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: min(1, root.children.count))
        }
    }
    let mruWindow = workspace.mostRecentWindowRecursive
    if let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer {
        return BindingData(
            parent: tilingParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: mruWindow.ownIndex.orDie() + 1,
        )
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter TallWindowInsertionTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/tree/MacWindow.swift Sources/AppBundleTests/tree/TallWindowInsertionTest.swift
git commit -m "Insert new windows at stack top in tall workspaces

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Config keys + workspace seeding + docs

**Files:**
- Modify: `Sources/AppBundle/config/parseConfig.swift` (two new parsers + registry entries)
- Modify: `Sources/AppBundle/tree/Workspace.swift` (seed `layoutMode` at workspace creation)
- Modify: `docs/config-examples/default-config.toml` (document the keys, commented to keep defaults)
- Modify test: `Sources/AppBundleTests/config/ConfigTest.swift`

**Interfaces:**
- Consumes: `Config.defaultWorkspaceLayout`, `Config.tallMasterRatioPercent`, `WorkspaceLayout` (Task 1).
- Produces: TOML keys `default-workspace-layout` (`'tiling'`|`'tall'`) and `tall-master-ratio` (int 1–99). New workspaces are seeded with `layoutMode = config.defaultWorkspaceLayout` at creation.

- [ ] **Step 1: Write failing config tests**

`parseConfig(_ toml: String) -> ParseConfigResult`, where `ParseConfigResult` has `let config: Config` and `let errors: [ConfigParseDiagnostic]` (Equatable, comparable to `[]`), plus a `.strErrors -> [String]` accessor used by the existing error-case tests. `ConfigTest` has **no** `setUp` and the tests are pure (they never touch the global `config`), so the two parse tests go here. The workspace-seeding test needs `setUpWorkspacesForTests`, so it goes in the Task 1 file instead (next step).

Add to `Sources/AppBundleTests/config/ConfigTest.swift`:

```swift
    func testParseDefaultWorkspaceLayout() {
        let result = parseConfig(
            """
            default-workspace-layout = 'tall'
            tall-master-ratio = 65
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.defaultWorkspaceLayout, .tall)
        assertEquals(result.config.tallMasterRatioPercent, 65)
    }

    func testTallMasterRatioOutOfRange() {
        let errors = parseConfig(
            """
            tall-master-ratio = 0
            """,
        ).strErrors
        assertEquals(errors, ["[ERROR] tall-master-ratio: tall-master-ratio must be an integer percentage in [1, 99]"])
    }
```

Add the seeding test to `Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift` (it already has `setUp { setUpWorkspacesForTests() }`):

```swift
    func testNewWorkspaceSeedsLayoutModeFromConfig() {
        config.defaultWorkspaceLayout = .tall
        let workspace = Workspace.get(byName: "freshly-created-tall-ws")
        assertEquals(workspace.layoutMode, .tall)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter ConfigTest` and `swift test --filter NormalizeTallWorkspaceTest/testNewWorkspaceSeedsLayoutModeFromConfig`
Expected: FAIL — the TOML keys are unknown (parse error) and `layoutMode` is not seeded.

- [ ] **Step 3: Add the parsers and registry entries**

In `Sources/AppBundle/config/parseConfig.swift`, add two parser functions near `parseDefaultContainerOrientation`:

```swift
private func parseWorkspaceLayout(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<WorkspaceLayout> {
    parseString(raw, backtrace).flatMap {
        WorkspaceLayout(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse workspace layout '\($0)'. Possible values: tiling, tall"))
    }
}

private func parseTallMasterRatioPercent(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    parseInt(raw, backtrace).flatMap {
        (1 ... 99).contains($0)
            ? .success($0)
            : .failure(.init(backtrace, "tall-master-ratio must be an integer percentage in [1, 99]"))
    }
}
```

Register both in the `configParser` dictionary (after the `default-root-container-*` entries):

```swift
    "default-workspace-layout": Parser(\.defaultWorkspaceLayout, parseWorkspaceLayout),
    "tall-master-ratio": Parser(\.tallMasterRatioPercent, parseTallMasterRatioPercent),
```

- [ ] **Step 4: Seed `layoutMode` at workspace creation**

In `Sources/AppBundle/tree/Workspace.swift`, in `get(byName:)`, set the mode when a workspace is first created:

```swift
    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspace.layoutMode = config.defaultWorkspaceLayout
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }
```

(Seeding only at creation means `reload-config` never stomps a workspace the user has manually switched.)

- [ ] **Step 5: Document the keys in the default config**

In `docs/config-examples/default-config.toml`, after the `default-root-container-orientation` block, add commented documentation (kept commented so the shipped defaults are unchanged):

```toml
# Possible values: 'tiling' (manual i3-like tiling), 'tall' (dynamic master-stack).
# New workspaces start in this layout.
# default-workspace-layout = 'tiling'

# Master column width as an integer percentage (1-99) for the 'tall' layout.
# tall-master-ratio = 50
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter ConfigTest` and `swift test --filter NormalizeTallWorkspaceTest`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppBundle/config/parseConfig.swift Sources/AppBundle/tree/Workspace.swift docs/config-examples/default-config.toml Sources/AppBundleTests/config/ConfigTest.swift Sources/AppBundleTests/tree/NormalizeTallWorkspaceTest.swift
git commit -m "Add default-workspace-layout and tall-master-ratio config keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Full build + suite + manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Full build**

Run: `./build-debug.sh` (or `swift build`)
Expected: builds with no errors. Fix any exhaustive-`switch` warnings/errors the compiler surfaces for the new `.tall` / `.promote` cases that weren't caught task-by-task.

- [ ] **Step 2: Full test suite**

Run: `swift test`
Expected: entire suite passes (no regressions in `LayoutCommandTest`, `MoveCommandTest`, `ConfigTest`, etc.).

- [ ] **Step 3: Manual smoke test**

Install the debug build and add temporary bindings to your config:

```toml
alt-t = 'layout tall tiles'
alt-shift-enter = 'promote'
```

Verify, in a real workspace:
1. `alt-t` turns a workspace with 3+ windows into master + vertical stack.
2. Opening a new window drops it at the top of the stack; the master is unchanged.
3. Closing the master promotes the stack-top window.
4. Focusing a stack window and pressing `alt-shift-enter` swaps it into master.
5. `resize` (your existing resize bindings) changes the master/stack split and the ratio survives opening/closing a window.
6. `alt-t` again returns the workspace to manual tiling with the windows intact.

- [ ] **Step 4: Commit (if any fixups were needed)**

```bash
git add -A
git commit -m "Fixups from full build and smoke test of tall layout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
