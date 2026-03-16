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
    @Published var isSidebarVisible: Bool = true
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

    /// Unshelve all shelved surfaces back into the tree as splits.
    func showAllSurfaces() {
        let toUnshelve = shelvedSurfaces
        for item in toUnshelve {
            unshelve(item)
        }
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
