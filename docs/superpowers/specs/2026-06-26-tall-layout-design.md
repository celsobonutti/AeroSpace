# Design: dynamic `tall` workspace layout

Date: 2026-06-26

## Goal

Add a dynamic master-stack layout to AeroSpace, equivalent to Amethyst's *Tall*
or xmonad's default *Tall* layout: one **master** window in a left column, and
all other windows split vertically in a right-hand **stack** column. The window
manager owns the arrangement and reflows automatically as windows are added,
removed, and reordered.

```
┌────────┬──────┐
│        │  W2  │
│   W1   ├──────┤
│ master │  W3  │
│        ├──────┤
│        │  W4  │
└────────┴──────┘
```

## Decisions (from brainstorming)

- **Dynamic, not static.** The WM auto-manages the arrangement: new windows flow
  in automatically, closing the master auto-promotes a stack window.
- **Workspace-scoped.** `tall` is a property of the *workspace*, not of an
  individual container. All tiling windows in the workspace participate.
- **Single master in v1.** Exactly one master window. Multi-master is out of scope.
- **Reuse existing commands.** Implemented by auto-maintaining a real tree, so the
  existing `focus` / `move` / `resize` machinery works unchanged. One new command,
  `promote`, swaps a stack window into the master slot.
- **New windows go to the top of the stack.** The master is never displaced by an
  incidental new window.
- **Default-on via config.** A workspace can start in tall mode.

## Core idea: `tall` is a workspace *mode*, not a render layout

AeroSpace already renders proportional tiling via `layoutTiles`. The master-stack
picture is exactly what `layoutTiles` produces for this canonical tree:

```
Workspace (layoutMode .tall, masterWindow = W1)
└─ rootTilingContainer        orientation .h, layout .tiles     ← left/right split
   ├─ W1   (master)                                             ← left column
   └─ stackContainer          orientation .v, layout .tiles     ← right column
      ├─ W2  ├─ W3  └─ W4                                        ← vertical stack
```

So **no new rendering algorithm is added**. `tall` is:

1. a per-workspace **mode flag**, plus
2. an **auto-reflow pass** that keeps the workspace tree in the canonical shape
   above, plus
3. a small amount of glue (new-window placement, the `promote` command, a couple
   of config keys).

Directional `focus`/`move` already traverse this tree correctly (focus-right goes
master → stack; focus-down moves within the stack). `resize` already adjusts the
root `.h` split weights, so the master ratio is free.

The `stackContainer` is only materialized when there are **≥2** windows. With one
window the root holds just the master (full screen); with zero the workspace is
empty.

## Data model

Two new stored fields on `Workspace`
(`Sources/AppBundle/tree/Workspace.swift`), with `fileprivate` storage and
accessors following the file's existing style:

- `layoutMode: WorkspaceLayout` — `enum WorkspaceLayout { case tiling, tall }`,
  default `.tiling`. Seeded from config at workspace creation (see Config).
- `masterWindow: Window?` — the master, tracked **by identity** so it survives
  reflows. `nil` until the first window appears or is chosen.

`WorkspaceLayout` is a new enum (distinct from the container-level `Layout`
enum, which stays `tiles`/`accordion`). It lives alongside `Workspace` or in
`Common` if a parser needs it.

## Reflow pass — `normalizeTallWorkspace()`

New file `Sources/AppBundle/tree/normalizeTallWorkspace.swift`, invoked from the
same place `normalizeContainers()` runs today (`refreshModel_nonCancellable` in
`Sources/AppBundle/layout/refresh.swift`).

`normalizeContainers()` branches on the workspace mode: for a `.tall` workspace it
runs `normalizeTallWorkspace()` **instead of** the normal
flatten + opposite-orientation normalization (those would collapse the
single-child stack container and flip orientations, fighting the canonical shape).

Algorithm (enforces the invariant — idempotent):

1. Collect all tiling windows in the workspace in current tree order → `windows`.
2. Determine the master:
   - if `masterWindow` is set and is still in `windows`, keep it;
   - otherwise master = `windows.first` and re-track it as `masterWindow`.
   This fallback is what **auto-promotes the stack-top when the master closes**.
3. Rebuild the canonical tree:
   - `0` windows → empty workspace, no containers;
   - `1` window → `rootTilingContainer` (`.h`/`.tiles`) holds just the master;
   - `≥2` windows → `rootTilingContainer` (`.h`/`.tiles`) holds
     `[master, stackContainer]`, where `stackContainer` is `.v`/`.tiles` and
     contains the remaining windows in their existing tree order.
4. Preserve the master's split weight (`hWeight`) across rebuilds so a
   user-adjusted master ratio sticks.

Order of stack windows = current tree order, so any reordering done by `move`
commands or by the new-window hook is respected.

## New-window placement → stack top

Hook `unbindAndGetBindingDataForNewTilingWindow`
(`Sources/AppBundle/tree/MacWindow.swift`, currently binds a new window right
after the MRU window in its parent).

For a `.tall` workspace, instead bind the new window at **index 0 of the stack
container** (creating the stack container if it doesn't exist yet), so the master
is never displaced and the freshest window appears at the top of the stack.
`normalizeTallWorkspace()` is the safety net for any other code path that adds a
window to a tall workspace (e.g. `move-node-to-workspace`).

## Commands

### `layout tall`

- Add `tall` to `LayoutDescription`
  (`Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift`).
- In `LayoutCommand` (`Sources/AppBundle/command/impl/LayoutCommand.swift`),
  `tall` resolves the **workspace** of the target (not just the focused
  container): set `workspace.layoutMode = .tall`, seed `masterWindow` = the
  currently focused window (if any), and trigger a reflow.
- Selecting any other layout description (`tiles`, `accordion`, `horizontal`,
  `vertical`, …) sets `layoutMode = .tiling`, leaving the current tree intact (it
  is already a valid manual tiling tree).
- Works with the existing toggle syntax, e.g. `layout tall tiles`.

### `promote` (new command)

Swaps the focused stack window into the master slot:

- old master takes the focused window's former stack position;
- `masterWindow` updated to the focused window;
- reflow.

If the focused window is already the master, it is a no-op (respect
`--fail-if-noop` convention if added). A dedicated command is used rather than the
existing `swap` (which targets directional/DFS neighbours, not "the master").

Registration checklist for the new command (the standard 6 sites):

1. `Sources/Common/cmdArgs/cmdArgsManifest.swift` — add `case promote` to
   `CmdKind` and a `case .promote` to `initSubcommands()`.
2. `Sources/Common/cmdArgs/impl/PromoteCmdArgs.swift` — new `PromoteCmdArgs`
   struct + `parsePromoteCmdArgs`.
3. `Sources/AppBundle/command/impl/PromoteCommand.swift` — new `PromoteCommand`.
4. `Sources/AppBundle/command/cmdManifest.swift` — add `case .promote` to
   `toCommand()`.
5. `docs/aerospace-promote.adoc` — synopsis/help source.
6. Run `./generate.sh` to regenerate `Sources/Common/cmdHelpGenerated.swift` and
   `docs/commands.adoc`.

## Navigation and movement

No new `focus` or `move` behavior is introduced. The canonical tree makes the
existing directional commands behave correctly:

- **Focus** — `focus left`/`focus right` cross the master↔stack boundary (the
  vertical split); `focus up`/`focus down` move within the stack (the `.v`
  container). (Cross-container directional focus is the standard i3-style
  behaviour AeroSpace already implements; verify during implementation that
  `focus right` from the master descends into the stack.)
- **Reordering the stack** — `move up`/`move down` on a stack window reorders the
  stack natively; the reflow preserves that order.
- **Changing the master** — the master is **identity-tracked and pinned**. Native
  `move`/`swap` on the master rearranges the tree, but the reflow snaps the tracked
  master back to the master slot, so generic commands never silently change who is
  master (they effectively no-op against the master). The master changes **only**
  via `promote`, which explicitly reassigns the tracked master window before
  reflowing.

This is why a `next`/`prev`-style command set is unnecessary: focus is spatial and
already works, and the single boundary-crossing operation (promote) is an explicit
command rather than an overloaded direction.

## Master ratio

No new resize command — the existing `resize` adjusts the root `.h` split weights,
which is exactly the master/stack ratio. Reflow preserves the weight so it sticks.

New config key seeds the initial split:

- **`tall-master-ratio`** — float, default `0.5`. Applied when entering tall mode
  or first materializing the master/stack split.

## Config

`Sources/AppBundle/config/parseConfig.swift`:

- **`default-workspace-layout`** — `'tiling'` (default) | `'tall'`. Seeded into a
  `Workspace`'s `layoutMode` at creation time, so newly-created workspaces start in
  tall and the first window becomes master automatically. Config **reload does not
  stomp** a workspace the user has manually switched with `layout tiles` (only
  affects workspaces created afterward / not yet instantiated).
- **`tall-master-ratio`** — float, default `0.5` (see Master ratio).

When a workspace is in `.tall` mode it overrides `default-root-container-layout`
and `default-root-container-orientation` (tall forces a `.h` root with `.tiles`).

## Edge cases (all handled by the reflow invariant)

- Master window closes → master no longer in `windows` → stack-top promoted.
- Last stack window closes → single window → master fills the screen.
- All windows close → empty workspace, no stray containers.
- User `move`s the master into the stack → it is demoted; next reflow makes the
  new slot-0 window the master (or `promote` is used for explicit control).
- `join-with` / `split` produce non-canonical structures → reflow normalizes them
  back to `[master, stackContainer]`.
- Moving a window into a tall workspace from elsewhere → reflow places it
  consistently (stack), master identity preserved.

## Out of scope (v1 / YAGNI)

- Multiple master windows and increase/decrease-master-count commands.
- A "wide" variant (master on top, stack along the bottom).
- Per-direction master placement (master is always the left column).

## Testing

New tests mirroring `Sources/AppBundleTests/command/LayoutCommandTest.swift`
(XCTest, `@MainActor`, `TestWindow`, `assertEquals`, `parseCommand`):

- `layout tall` on a workspace with N windows builds the canonical tree
  (`[master, stackContainer(.v)]`) and sets `layoutMode = .tall`.
- A newly-added window lands at the **top** of the stack; master unchanged.
- Closing the master promotes the stack-top to master.
- `promote` swaps the focused stack window with the master and updates tracking.
- `resize` changes the master ratio and the ratio **persists across a reflow**.
- `layout tiles` (or any non-tall description) clears tall mode and leaves a valid
  tree.
- `default-workspace-layout = 'tall'` makes a freshly-created workspace start tall;
  reload preserving a manually-switched workspace.

## File-by-file change list

| Area | File |
|------|------|
| Workspace state (`layoutMode`, `masterWindow`) + `WorkspaceLayout` enum | `Sources/AppBundle/tree/Workspace.swift` |
| Reflow pass | `Sources/AppBundle/tree/normalizeTallWorkspace.swift` (new) |
| Branch normalization on mode | `Sources/AppBundle/tree/normalizeContainers.swift` |
| Invoke reflow in refresh loop | `Sources/AppBundle/layout/refresh.swift` |
| New-window placement hook | `Sources/AppBundle/tree/MacWindow.swift` |
| `tall` layout keyword | `Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift` |
| `layout tall` workspace-mode handling | `Sources/AppBundle/command/impl/LayoutCommand.swift` |
| `promote` command (6 registration sites) | `cmdArgsManifest.swift`, `PromoteCmdArgs.swift`, `PromoteCommand.swift`, `cmdManifest.swift`, `docs/aerospace-promote.adoc`, `generate.sh` |
| Config keys (`default-workspace-layout`, `tall-master-ratio`) | `Sources/AppBundle/config/parseConfig.swift` |
| Tests | `Sources/AppBundleTests/command/` (+ tall-specific test file) |
