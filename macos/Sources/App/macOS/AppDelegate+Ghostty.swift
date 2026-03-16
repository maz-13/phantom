import AppKit

// MARK: Ghostty Delegate

/// This implements the Ghostty app delegate protocol which is used by the Ghostty
/// APIs for app-global information.
extension AppDelegate: Ghostty.Delegate {
    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }

            // Also check shelved surfaces so drag-and-drop from the sidebar works.
            if let shelved = controller.layoutManager.shelvedSurfaces.first(where: { $0.surface.id == id }) {
                return shelved.surface
            }
        }

        return nil
    }
}
