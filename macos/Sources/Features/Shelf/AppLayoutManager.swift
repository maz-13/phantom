import AppKit
import Combine
import SwiftUI

// MARK: - Data Types

struct SidebarItem: Identifiable {
    enum State { case focused, active, shelved }
    let id: UUID
    let surface: Ghostty.SurfaceView
    let shelvedSurface: ShelvedSurface?   // non-nil only when .shelved
    var state: State
    var hasActivity: Bool
    var needsAttention: Bool
    var displayName: String
}

struct ShelvedSurface: Identifiable {
    let id: UUID = UUID()
    let surface: Ghostty.SurfaceView
    var customName: String?
    var hasActivity: Bool = false
    var hasBeenActive: Bool = false
    var needsAttention: Bool = false
    let shelvedAt: Date = Date()

    var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        return "Terminal"
    }
}

// MARK: - AppLayoutManager

class AppLayoutManager: ObservableObject {

    @Published private(set) var shelvedSurfaces: [ShelvedSurface] = []
    @Published private(set) var sidebarItems: [SidebarItem] = []
    @Published var isSidebarVisible: Bool = false
    @Published var isSidebarOverlaying: Bool = false

    private weak var controller: BaseTerminalController?

    /// Title-change observers keyed by ShelvedSurface.id, used to animate the activity spinner.
    private var titleObservers: [UUID: AnyCancellable] = [:]

    /// PWD observers keyed by ShelvedSurface.id, used to detect when a command finishes.
    private var pwdObservers: [UUID: AnyCancellable] = [:]

    /// Activity reset timers keyed by ShelvedSurface.id.
    private var activityResetTimers: [UUID: Timer] = [:]

    /// Timestamp of last title change per surface, for rate-limiting the spinner trigger.
    private var lastTitleChangeTimes: [UUID: Date] = [:]

    private var surfaceTreeCancellable: AnyCancellable?

    /// Stable insertion-order list of all surface IDs ever seen, used to keep sidebar order static.
    private var surfaceOrder: [UUID] = []

    /// Snapshot of the split layout saved before unshelving a panel as sole view.
    /// Cmd+Z restores this. Only set once per "sequence" — chained tab clicks don't overwrite it.
    var savedLayout: SplitTree<Ghostty.SurfaceView>? = nil

    init(controller: BaseTerminalController) {
        self.controller = controller
        surfaceTreeCancellable = controller.$surfaceTree
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSidebarItems() }
    }

    // MARK: - Sidebar Items

    func rebuildSidebarItems() {
        guard let controller else { sidebarItems = []; return }
        let focused = controller.focusedSurface
        let treeMap = Dictionary(uniqueKeysWithValues: Array(controller.surfaceTree).map { ($0.id, $0) })
        let shelfMap = Dictionary(uniqueKeysWithValues: shelvedSurfaces.map { ($0.surface.id, $0) })

        // Register any new surfaces not yet tracked
        for id in treeMap.keys where !surfaceOrder.contains(id) {
            surfaceOrder.append(id)
        }
        for id in shelfMap.keys where !surfaceOrder.contains(id) {
            surfaceOrder.append(id)
        }
        // Drop IDs that are gone entirely (closed, not in tree or shelf)
        surfaceOrder = surfaceOrder.filter { treeMap[$0] != nil || shelfMap[$0] != nil }

        // Build items in stable order
        sidebarItems = surfaceOrder.compactMap { id in
            if let surface = treeMap[id] {
                let state: SidebarItem.State = (surface.id == focused?.id) ? .focused : .active
                return SidebarItem(id: id, surface: surface, shelvedSurface: nil,
                    state: state, hasActivity: false, needsAttention: false, displayName: "Terminal")
            } else if let shelved = shelfMap[id] {
                return SidebarItem(id: id, surface: shelved.surface, shelvedSurface: shelved,
                    state: .shelved, hasActivity: shelved.hasActivity,
                    needsAttention: shelved.needsAttention, displayName: shelved.displayName)
            }
            return nil
        }
    }

    func focusActiveSurface(_ surface: Ghostty.SurfaceView) {
        guard let controller else { return }
        guard Array(controller.surfaceTree).contains(where: { $0.id == surface.id }) else { return }
        Ghostty.moveFocus(to: surface, from: controller.focusedSurface)
    }

    // MARK: - Sidebar

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
        }
    }

    // MARK: - Shelving

    func shelveCurrentSurface() {
        guard let controller, let surface = controller.focusedSurface else { return }
        guard Array(controller.surfaceTree).count > 1 else { return }
        shelve(surface: surface)
    }

    /// Shelve every surface in the tree except the currently focused one.
    func shelveAllExceptFocused() {
        guard let controller else { return }
        guard let focused = controller.focusedSurface else { return }
        let allSurfaces = Array(controller.surfaceTree)
        guard allSurfaces.count > 1 else { return }
        let toShelve = allSurfaces.filter { $0.id != focused.id }
        for surface in toShelve {
            shelve(surface: surface)
        }
        if !isSidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible = true }
        }
    }

    /// Arrange all surfaces (visible + shelved) into an even grid layout.
    func showAllSurfaces() {
        guard let controller else { return }

        // Collect every surface: currently in the tree + all shelved
        let visibleSurfaces = Array(controller.surfaceTree)
        let shelvedSurfaceViews = shelvedSurfaces.map { $0.surface }
        let allSurfaces = visibleSurfaces + shelvedSurfaceViews

        // Clear shelf state
        for item in shelvedSurfaces {
            titleObservers.removeValue(forKey: item.id)
            pwdObservers.removeValue(forKey: item.id)
            lastTitleChangeTimes.removeValue(forKey: item.id)
            activityResetTimers[item.id]?.invalidate()
            activityResetTimers.removeValue(forKey: item.id)
        }
        shelvedSurfaces.removeAll()

        guard !allSurfaces.isEmpty else { return }

        // Build a fresh grid tree and apply it
        controller.surfaceTree = buildGridTree(allSurfaces)

        withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible = false }
        rebuildSidebarItems()
    }

    // MARK: - Grid Layout

    /// Build a SplitTree with the given surfaces arranged in an even grid.
    private func buildGridTree(_ surfaces: [Ghostty.SurfaceView]) -> SplitTree<Ghostty.SurfaceView> {
        guard !surfaces.isEmpty else { return SplitTree() }
        return SplitTree<Ghostty.SurfaceView>(root: buildGridNode(surfaces), zoomed: nil)
    }

    /// Recursively build the root Node for the given surfaces using a grid layout.
    private func buildGridNode(_ surfaces: [Ghostty.SurfaceView]) -> SplitTree<Ghostty.SurfaceView>.Node {
        let n = surfaces.count
        let rows = Int(ceil(Double(n) / 3.0))
        let base = n / rows
        let extra = n % rows

        // Distribute panels across rows — extra panels go to the bottom rows
        var distribution: [Int] = Array(repeating: base, count: rows)
        for i in (rows - extra)..<rows { distribution[i] += 1 }

        // Build each row's node
        var rowNodes: [SplitTree<Ghostty.SurfaceView>.Node] = []
        var offset = 0
        for count in distribution {
            rowNodes.append(buildRowNode(Array(surfaces[offset..<offset + count])))
            offset += count
        }

        return buildVerticalStack(rowNodes)
    }

    /// Build a left-leaning chain of horizontal splits for a single row of panels.
    /// Each panel gets equal width via ratio = (N-1)/N at each nesting level.
    private func buildRowNode(_ surfaces: [Ghostty.SurfaceView]) -> SplitTree<Ghostty.SurfaceView>.Node {
        let n = surfaces.count
        if n == 1 { return .leaf(view: surfaces[0]) }
        let ratio = Double(n - 1) / Double(n)
        return .split(.init(
            direction: .horizontal,
            ratio: ratio,
            left: buildRowNode(Array(surfaces[0..<n - 1])),
            right: .leaf(view: surfaces[n - 1])
        ))
    }

    /// Stack multiple row nodes vertically with equal height.
    private func buildVerticalStack(_ nodes: [SplitTree<Ghostty.SurfaceView>.Node]) -> SplitTree<Ghostty.SurfaceView>.Node {
        let n = nodes.count
        if n == 1 { return nodes[0] }
        let ratio = Double(n - 1) / Double(n)
        return .split(.init(
            direction: .vertical,
            ratio: ratio,
            left: buildVerticalStack(Array(nodes[0..<n - 1])),
            right: nodes[n - 1]
        ))
    }

    func shelve(surface: Ghostty.SurfaceView) {
        guard let controller else { return }
        guard let node = controller.surfaceTree.find(id: surface.id) else { return }
        guard Array(controller.surfaceTree).count > 1 else { return }
        controller.surfaceTree = controller.surfaceTree.removing(node)
        addToShelf(surface: surface)
    }

    /// Shelve a surface that has already been removed from the tree (caller already replaced surfaceTree).
    func shelveDetached(surface: Ghostty.SurfaceView) {
        addToShelf(surface: surface)
    }

    private func addToShelf(surface: Ghostty.SurfaceView) {
        let shelvedSurface = ShelvedSurface(surface: surface)
        shelvedSurfaces.append(shelvedSurface)

        let id = shelvedSurface.id

        // Title observer: spinner activates only on rapid changes (2 within 10s),
        // filtering out one-off shell prompt title updates.
        titleObservers[id] = surface.$title
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                let now = Date()
                let last = self.lastTitleChangeTimes[id]
                self.lastTitleChangeTimes[id] = now
                guard let last, now.timeIntervalSince(last) < 10.0 else { return }
                if let idx = self.shelvedSurfaces.firstIndex(where: { $0.id == id }) {
                    self.shelvedSurfaces[idx].hasActivity = true
                    self.shelvedSurfaces[idx].hasBeenActive = true
                    self.shelvedSurfaces[idx].needsAttention = false
                    self.scheduleActivityReset(for: id)
                }
            }

        // PWD observer: fires when the shell returns to the prompt (OSC 7).
        // Immediately marks the surface as needing attention if it was previously active.
        pwdObservers[id] = surface.$pwd
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                if let idx = self.shelvedSurfaces.firstIndex(where: { $0.id == id }) {
                    guard self.shelvedSurfaces[idx].hasBeenActive else { return }
                    self.activityResetTimers[id]?.invalidate()
                    self.activityResetTimers.removeValue(forKey: id)
                    self.shelvedSurfaces[idx].hasActivity = false
                    self.shelvedSurfaces[idx].needsAttention = true
                }
            }
    }

    private func scheduleActivityReset(for id: UUID) {
        activityResetTimers[id]?.invalidate()
        activityResetTimers[id] = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let idx = self.shelvedSurfaces.firstIndex(where: { $0.id == id }) {
                    self.shelvedSurfaces[idx].hasActivity = false
                    self.shelvedSurfaces[idx].needsAttention = true
                }
                self.activityResetTimers.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Unshelving

    /// Replace all visible surfaces with the given shelved surface (browser-tab behavior).
    /// All currently visible surfaces are shelved, and only this surface is shown.
    func unshelveAsSole(_ shelvedSurface: ShelvedSurface) {
        guard let controller else { return }
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }

        titleObservers.removeValue(forKey: shelvedSurface.id)
        pwdObservers.removeValue(forKey: shelvedSurface.id)
        lastTitleChangeTimes.removeValue(forKey: shelvedSurface.id)
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)

        let surface = shelvedSurface.surface

        // Capture current surfaces before replacing the tree.
        // We set the new tree first to avoid ever passing through an empty tree
        // (an empty tree triggers window close in TerminalController).
        let currentSurfaces = Array(controller.surfaceTree)
        let previousFocus = controller.focusedSurface

        // Snapshot the current layout for Cmd+Z restore (only on the first tab switch).
        if savedLayout == nil {
            savedLayout = controller.surfaceTree
        }

        controller.surfaceTree = .init(view: surface)

        // Shelve the previous surfaces now that they've been removed from the tree.
        for current in currentSurfaces {
            shelveDetached(surface: current)
        }

        // Explicitly move focus so focusedSurface updates and the sidebar highlight reflects correctly.
        Ghostty.moveFocus(to: surface, from: previousFocus)
        rebuildSidebarItems()
    }

    /// Restore the split layout that was active before the last unshelveAsSole call (Cmd+Z).
    func restorePreviousLayout() {
        guard let controller, let layout = savedLayout else { return }
        let currentSurfaces = Array(controller.surfaceTree)
        controller.surfaceTree = layout
        for surface in currentSurfaces {
            if !Array(layout).contains(where: { $0.id == surface.id }) {
                shelveDetached(surface: surface)
            }
        }
        savedLayout = nil
        rebuildSidebarItems()
    }

    /// Close an active (in-tree) surface from the sidebar.
    /// - Multiple panels open: removes it, remaining panels stay.
    /// - Only panel visible, shelved panels exist: shows the next shelved one.
    /// - Only panel everywhere: no-op.
    func closeActive(_ surface: Ghostty.SurfaceView) {
        guard let controller else { return }
        let tree = Array(controller.surfaceTree)
        guard tree.contains(where: { $0.id == surface.id }) else { return }
        guard !(tree.count == 1 && shelvedSurfaces.isEmpty) else { return }

        savedLayout = nil

        if tree.count > 1 {
            // Remove from split — remaining panels stay visible
            if let node = controller.surfaceTree.find(id: surface.id) {
                controller.surfaceTree = controller.surfaceTree.removing(node)
            }
        } else {
            // Only visible panel — promote the first shelved surface
            let next = shelvedSurfaces[0]
            titleObservers.removeValue(forKey: next.id)
            pwdObservers.removeValue(forKey: next.id)
            lastTitleChangeTimes.removeValue(forKey: next.id)
            activityResetTimers[next.id]?.invalidate()
            activityResetTimers.removeValue(forKey: next.id)
            shelvedSurfaces.removeFirst()
            controller.surfaceTree = .init(view: next.surface)
            Ghostty.moveFocus(to: next.surface, from: surface)
        }
        rebuildSidebarItems()
    }

    /// Remove a surface from the shelf without inserting it into the tree.
    /// The caller is responsible for inserting the surface elsewhere to keep it alive.
    func dequeueFromShelf(_ shelvedSurface: ShelvedSurface) {
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }
        titleObservers.removeValue(forKey: shelvedSurface.id)
        pwdObservers.removeValue(forKey: shelvedSurface.id)
        lastTitleChangeTimes.removeValue(forKey: shelvedSurface.id)
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)
        rebuildSidebarItems()
    }

    /// Bring a shelved surface back as a split alongside the currently focused surface.
    func unshelve(_ shelvedSurface: ShelvedSurface) {
        guard let controller else { return }
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }

        titleObservers.removeValue(forKey: shelvedSurface.id)
        pwdObservers.removeValue(forKey: shelvedSurface.id)
        lastTitleChangeTimes.removeValue(forKey: shelvedSurface.id)
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)
        let surface = shelvedSurface.surface

        if controller.surfaceTree.isEmpty {
            controller.surfaceTree = .init(view: surface)
            return
        }

        let anchor = controller.focusedSurface ?? controller.surfaceTree.first
        if let anchor,
           let newTree = try? controller.surfaceTree.inserting(view: surface, at: anchor, direction: .right) {
            controller.surfaceTree = newTree
        } else if let first = controller.surfaceTree.first,
                  let newTree = try? controller.surfaceTree.inserting(view: surface, at: first, direction: .right) {
            controller.surfaceTree = newTree
        }
    }

    // MARK: - Closing

    /// Permanently close and discard a shelved surface, killing its process.
    func close(_ shelvedSurface: ShelvedSurface) {
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }
        titleObservers.removeValue(forKey: shelvedSurface.id)
        pwdObservers.removeValue(forKey: shelvedSurface.id)
        lastTitleChangeTimes.removeValue(forKey: shelvedSurface.id)
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)
        // Releasing the SurfaceView here causes ghostty_surface_free via Ghostty.Surface.deinit
        rebuildSidebarItems()
    }
}
