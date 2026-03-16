import AppKit
import Combine
import SwiftUI

// MARK: - Data Types

struct ShelvedSurface: Identifiable {
    let id: UUID = UUID()
    let surface: Ghostty.SurfaceView
    var customName: String?
    var hasActivity: Bool = false
    let shelvedAt: Date = Date()

    var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        return "Terminal"
    }
}

// MARK: - AppLayoutManager

class AppLayoutManager: ObservableObject {

    @Published private(set) var shelvedSurfaces: [ShelvedSurface] = []
    @Published var isSidebarVisible: Bool = false
    @Published var isSidebarOverlaying: Bool = false

    private weak var controller: BaseTerminalController?

    /// Title-change observers keyed by ShelvedSurface.id, used to animate the activity spinner.
    private var titleObservers: [UUID: AnyCancellable] = [:]

    /// Activity reset timers keyed by ShelvedSurface.id.
    private var activityResetTimers: [UUID: Timer] = [:]

    init(controller: BaseTerminalController) {
        self.controller = controller
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
            activityResetTimers[item.id]?.invalidate()
            activityResetTimers.removeValue(forKey: item.id)
        }
        shelvedSurfaces.removeAll()

        guard !allSurfaces.isEmpty else { return }

        // Build a fresh grid tree and apply it
        controller.surfaceTree = buildGridTree(allSurfaces)

        withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible = false }
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

        // Observe title changes to drive the activity spinner
        let id = shelvedSurface.id
        titleObservers[id] = surface.$title
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                if let idx = self.shelvedSurfaces.firstIndex(where: { $0.id == id }) {
                    self.shelvedSurfaces[idx].hasActivity = true
                    self.scheduleActivityReset(for: id)
                }
            }
    }

    private func scheduleActivityReset(for id: UUID) {
        activityResetTimers[id]?.invalidate()
        activityResetTimers[id] = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let idx = self.shelvedSurfaces.firstIndex(where: { $0.id == id }) {
                    self.shelvedSurfaces[idx].hasActivity = false
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
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)

        let surface = shelvedSurface.surface

        // Capture current surfaces before replacing the tree.
        // We set the new tree first to avoid ever passing through an empty tree
        // (an empty tree triggers window close in TerminalController).
        let currentSurfaces = Array(controller.surfaceTree)
        controller.surfaceTree = .init(view: surface)

        // Shelve the previous surfaces now that they've been removed from the tree.
        for current in currentSurfaces {
            shelveDetached(surface: current)
        }
    }

    /// Remove a surface from the shelf without inserting it into the tree.
    /// The caller is responsible for inserting the surface elsewhere to keep it alive.
    func dequeueFromShelf(_ shelvedSurface: ShelvedSurface) {
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }
        titleObservers.removeValue(forKey: shelvedSurface.id)
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)
    }

    /// Bring a shelved surface back as a split alongside the currently focused surface.
    func unshelve(_ shelvedSurface: ShelvedSurface) {
        guard let controller else { return }
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }

        titleObservers.removeValue(forKey: shelvedSurface.id)
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
        activityResetTimers[shelvedSurface.id]?.invalidate()
        activityResetTimers.removeValue(forKey: shelvedSurface.id)
        shelvedSurfaces.remove(at: index)
        // Releasing the SurfaceView here causes ghostty_surface_free via Ghostty.Surface.deinit
    }
}
