# CLAUDE.md — Phantom

Phantom is a behavioral fork of [Ghostty](https://github.com/ghostty-org/ghostty). It adds a surface shelf and sidebar to the stock macOS app with no visual redesign.

**Repo:** https://github.com/maz-13/phantom
**Upstream:** https://github.com/ghostty-org/ghostty (remote: `origin`)
**Local path:** `~/cowork/phantom`

---

## Core Principle

> Stay behavioral, not visual. Add capabilities; don't redesign Ghostty.

Visual changes (custom window chrome, themes, XIB redesigns) create constant upstream merge friction for low value. Behavioral features in isolated files are merge-resilient and survive upstream updates.

---

## Project Structure

### Phantom-owned files (safe to edit freely)
```
macos/Sources/Features/Shelf/
  AppLayoutManager.swift       — shelf state, grid builder, all shelf logic
  SurfaceShelfView.swift       — sidebar SwiftUI UI
  SidebarEdgeHoverStrip.swift  — hover strip for overlay sidebar
```

### Upstream files Phantom hooks into (edit carefully)
```
macos/Sources/Features/Terminal/BaseTerminalController.swift
macos/Sources/Features/Terminal/TerminalController.swift
macos/Sources/Features/Terminal/TerminalView.swift
macos/Sources/App/macOS/AppDelegate.swift
macos/Sources/App/macOS/AppDelegate+Ghostty.swift
```
These files are owned by Ghostty. Every line Phantom adds here is a future merge conflict risk. Keep additions minimal and additive (append, don't replace).

---

## Development Rules

### Rule 1 — New features go in Shelf/ first
Before touching any upstream file, ask: can this live entirely in `AppLayoutManager.swift` or a new file in `Shelf/`? Most shelf features can. Only add hooks into upstream files when truly necessary.

### Rule 2 — Upstream file edits must be additive
When editing an upstream file (BaseTerminalController, TerminalView, etc.):
- **Add** new properties, methods, extensions — don't replace existing logic
- **Never** delete or restructure upstream code to make room for Phantom features
- If you must modify an existing method, make the smallest possible surgical change

### Rule 3 — Keep hooks in extension files
Don't inline Phantom code into the middle of upstream methods. Instead, add extension files:
- `BaseTerminalController+Shelf.swift` for shelf-related IBActions and event hooks
- `TerminalView+Shelf.swift` for sidebar view wrappers

Extension files are never touched by upstream merges.

### Rule 4 — Mark every upstream file touch with a comment
At every point where Phantom code is injected into an upstream file, add:
```swift
// PHANTOM: <one-line reason>
```
This makes `grep -r "PHANTOM:" macos/` a complete inventory of merge-sensitive lines. Check these comments after every upstream merge.

### Rule 5 — No XIB edits except renaming
XIB files are XML — merge conflicts in them are painful and often corrupt the file. The only acceptable XIB change is the Ghostty → Phantom name rename. No layout or behavior changes in XIBs.

### Rule 6 — The "Ghostty → Phantom" string list
These are the only string renames from upstream. Verify them after every merge:
- `AppDelegate.swift` — "Quit Phantom?", "Close Phantom", "Allow Phantom to execute", "Phantom could not be set"
- `TerminalView.swift` — debug build warning strings

If upstream changes these source strings, re-apply the rename. Keep this list up to date here.

---

## Upstream Merge Process

Merge upstream **monthly** — before the gap compounds.

```bash
# 1. Fetch upstream
git fetch origin

# 2. Check what's incoming and whether it touches Phantom's files
git log --oneline origin/main ^HEAD
git diff HEAD origin/main --name-only

# 3. If any of these files appear in the diff, read the upstream changes before merging:
#    BaseTerminalController.swift, TerminalController.swift, TerminalView.swift,
#    AppDelegate.swift, AppDelegate+Ghostty.swift, SplitTree.swift

# 4. Merge
git merge origin/main

# 5. After merge, verify all PHANTOM: markers are intact
grep -r "PHANTOM:" macos/Sources/

# 6. Re-apply Ghostty → Phantom string renames if any were clobbered (see Rule 6)

# 7. Build and test
xattr -cr macos/build/Release/Phantom.app 2>/dev/null
nu macos/build.nu --configuration Release --action build && \
xattr -cr macos/build/Release/Phantom.app && \
codesign --force --deep --sign - macos/build/Release/Phantom.app && \
open macos/build/Release/Phantom.app
```

### High-risk upstream changes to watch for
| File | What would break Phantom |
|---|---|
| `SplitTree.swift` | `.find()`, `.removing()`, `.inserting()`, `.Node`, `root:zoomed:` constructor |
| `BaseTerminalController.swift` | `surfaceTree` property, event monitor setup, `surfaceTreeDidChange` |
| `TerminalView.swift` | Root view layout restructure (the ZStack/VStack/HStack hierarchy) |
| `TerminalController.swift` | `newTab` IBAction, `TerminalView` init signature |

---

## Architecture

### How the shelf works
1. `AppLayoutManager` (an `ObservableObject`) is a lazy property on `BaseTerminalController`
2. It observes `controller.$surfaceTree` via Combine to keep the sidebar list in sync
3. Shelving a surface calls `SplitTree.removing()` to pull it from the live tree, stores it in `shelvedSurfaces: [ShelvedSurface]`
4. Unshelving calls `SplitTree.inserting()` to put it back, or `buildGridTree()` for show-all
5. The sidebar is a SwiftUI `SurfaceShelfView` injected into `TerminalView` as the leading element of an `HStack`
6. Keyboard shortcuts are intercepted via a `localEventMonitor` in `BaseTerminalController` (runs before Ghostty's own key handling)

### SplitTree API Phantom depends on
```swift
SplitTree<Ghostty.SurfaceView>()                          // empty init
SplitTree<Ghostty.SurfaceView>(root:zoomed:)              // full init
tree.find(id:)                                             // find a node
tree.removing(_ node:)                                     // remove a surface
tree.inserting(view:at:direction:) { newSurface in ... }  // insert a surface
Array(tree)                                                // iterate all surfaces
SplitTree.Node                                             // node type
```
If upstream changes any of these, update `AppLayoutManager.swift` to match.

### Keyboard shortcuts
All shortcuts are intercepted in `BaseTerminalController.localEventKeyDown` (not via `NSMenuItem` key equivalents, because Ghostty intercepts keyDown at the app level first). Menu items in `AppDelegate` are for discoverability only and are deliberately non-functional via the responder chain.

| Shortcut | Action |
|---|---|
| Cmd+Shift+S | Shelve all except focused |
| Cmd+Shift+H | Shelve current surface |
| Cmd+Shift+A | Show all shelved surfaces |
| Cmd+S | Toggle sidebar |

---

## Build Commands

```bash
# Full build + launch (use this)
xattr -cr macos/build/Release/Phantom.app 2>/dev/null
nu macos/build.nu --configuration Release --action build && \
xattr -cr macos/build/Release/Phantom.app && \
codesign --force --deep --sign - macos/build/Release/Phantom.app && \
open macos/build/Release/Phantom.app

# Launch only (already built)
xattr -cr macos/build/Release/Phantom.app && \
codesign --force --deep --sign - macos/build/Release/Phantom.app && \
open macos/build/Release/Phantom.app

# Debug build (shows performance warning — avoid for normal use)
nu macos/build.nu --configuration Debug --action build
```

---

## Git Remotes

```
origin   https://github.com/ghostty-org/ghostty   ← upstream Ghostty
fork     https://github.com/maz-13/phantom         ← Phantom's GitHub
```

Push Phantom changes to `fork`. Pull upstream updates from `origin`.

---

## What to Build Next

Good candidates — all achievable within `Shelf/` files with minimal upstream hooks:

- **Named sessions** — save/restore shelf states by name
- **Shelf persistence** — serialize shelved surfaces across app restarts
- **Cmd+number shortcuts** — jump directly to shelved surface N (like browser tabs)
- **Per-window vs. global shelf** — option to scope shelf to one window or share across all

Avoid:
- Custom window chrome or titlebar changes (high XIB conflict risk)
- Overriding Ghostty config options (high `Config.zig` / `Config.swift` conflict risk)
- Features that require changes to the Zig core (very high maintenance burden)
