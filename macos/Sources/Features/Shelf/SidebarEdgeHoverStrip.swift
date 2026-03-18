import AppKit
import SwiftUI

/// A transparent NSView-based hover strip placed at the left edge of the window.
/// Uses NSTrackingArea so hover detection works even over NSView-backed terminal surfaces,
/// where SwiftUI's .onHover is unreliable.
struct SidebarEdgeHoverStrip: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onEnter = {
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = true }
        }
        view.onExit = {
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = false }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    class TrackingView: NSView {
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?

        private var trackingArea: NSTrackingArea?

        // Use .inVisibleRect so AppKit owns the rect and updates it automatically on
        // bounds changes. This avoids recreating the tracking area on every resize event,
        // which was causing main-thread stalls during window resize at 60fps.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, trackingArea == nil else { return }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onEnter?()
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }

        /// Return nil so mouse clicks pass through to views behind this one.
        /// NSTrackingArea enter/exit events are still delivered regardless.
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}
