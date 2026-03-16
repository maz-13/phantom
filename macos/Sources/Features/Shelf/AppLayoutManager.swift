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
        let title = surface.title
        if !title.isEmpty { return title }
        return "Terminal"
    }
}

// MARK: - AppLayoutManager

class AppLayoutManager: ObservableObject {

    @Published private(set) var shelvedSurfaces: [ShelvedSurface] = []
    @Published private(set) var isFocusModeActive: Bool = false

    private weak var controller: BaseTerminalController?

    init(controller: BaseTerminalController) {
        self.controller = controller
    }

    // MARK: - Focus Mode

    func toggleFocusMode() {
        if isFocusModeActive {
            exitFocusMode()
        } else {
            enterFocusMode()
        }
    }

    private func enterFocusMode() {
        guard let controller else { return }
        guard let focused = controller.focusedSurface ?? controller.surfaceTree.first else { return }

        let allSurfaces = Array(controller.surfaceTree)
        let toShelve = allSurfaces.filter { $0 !== focused }
        guard !toShelve.isEmpty else { return }

        isFocusModeActive = true
        for surface in toShelve {
            shelve(surface: surface)
        }
    }

    /// Exit focus mode: bring ALL shelved surfaces back and arrange in a grid.
    private func exitFocusMode() {
        guard let controller else {
            isFocusModeActive = false
            return
        }

        let currentSurfaces = Array(controller.surfaceTree)
        let shelvedViews = shelvedSurfaces.map { $0.surface }
        let allSurfaces = currentSurfaces + shelvedViews

        shelvedSurfaces.removeAll()
        isFocusModeActive = false

        if let newTree = buildGridTree(surfaces: allSurfaces) {
            controller.surfaceTree = newTree
        }
    }

    // MARK: - Shelving

    func shelveCurrentSurface() {
        guard let controller, let surface = controller.focusedSurface else { return }
        guard Array(controller.surfaceTree).count > 1 else { return }
        shelve(surface: surface)
    }

    func shelve(surface: Ghostty.SurfaceView) {
        guard let controller else { return }
        guard let node = controller.surfaceTree.find(id: surface.id) else { return }
        guard Array(controller.surfaceTree).count > 1 else { return }
        controller.surfaceTree = controller.surfaceTree.removing(node)
        shelvedSurfaces.append(ShelvedSurface(surface: surface))
    }

    // MARK: - Unshelving

    /// Bring a shelved surface back as a split alongside the currently focused surface.
    func unshelve(_ shelvedSurface: ShelvedSurface) {
        guard let controller else { return }
        guard let index = shelvedSurfaces.firstIndex(where: { $0.id == shelvedSurface.id }) else { return }

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

    // MARK: - Grid Layout

    /// Build a balanced grid tree from a list of surfaces.
    ///
    /// Layout rules:
    /// - 1–3 surfaces: single row of vertical splits
    /// - 4+ surfaces: two rows, bottom row gets ceil(n/2), top gets the rest
    private func buildGridTree(surfaces: [Ghostty.SurfaceView]) -> SplitTree<Ghostty.SurfaceView>? {
        guard !surfaces.isEmpty else { return nil }
        if surfaces.count == 1 { return .init(view: surfaces[0]) }

        let n = surfaces.count

        if n <= 3 {
            // Single row: chain .right inserts
            var tree = SplitTree<Ghostty.SurfaceView>(view: surfaces[0])
            for i in 1..<n {
                tree = (try? tree.inserting(view: surfaces[i], at: surfaces[i - 1], direction: .right)) ?? tree
            }
            return tree
        }

        // Two rows
        let row2Count = (n + 1) / 2   // ceil(n/2) — bottom row (gets more if odd)
        let row1Count = n - row2Count  // top row

        let row1 = Array(surfaces[0..<row1Count])
        let row2 = Array(surfaces[row1Count...])

        // Start with anchor (first of row1), add first of row2 below it
        var tree = SplitTree<Ghostty.SurfaceView>(view: row1[0])
        tree = (try? tree.inserting(view: row2[0], at: row1[0], direction: .down)) ?? tree

        // Fill rest of row1 (right of row1[0])
        for i in 1..<row1Count {
            tree = (try? tree.inserting(view: row1[i], at: row1[i - 1], direction: .right)) ?? tree
        }

        // Fill rest of row2 (right of row2[0])
        for i in 1..<row2Count {
            tree = (try? tree.inserting(view: row2[i], at: row2[i - 1], direction: .right)) ?? tree
        }

        return tree
    }
}
