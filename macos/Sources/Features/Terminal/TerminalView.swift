import SwiftUI
import GhosttyKit
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: Ghostty.SurfaceView)

    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<Ghostty.SurfaceView> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }

    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Ghostty.App

    // The required view model
    @ObservedObject var viewModel: ViewModel

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)?

    // Optional layout manager for the shelf sidebar.
    var layoutManager: AppLayoutManager? = nil

    /// The most recently focused surface, equal to `focusedSurface` when it is non-nil.
    @State private var lastFocusedSurface: Weak<Ghostty.SurfaceView>?

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface
    @FocusedValue(\.ghosttySurfacePwd) private var surfacePwd
    @FocusedValue(\.ghosttySurfaceCellSize) private var cellSize

    // The pwd of the focused surface as a URL
    private var pwdURL: URL? {
        guard let surfacePwd, surfacePwd != "" else { return nil }
        return URL(fileURLWithPath: surfacePwd)
    }

    var body: some View {
        switch ghostty.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            ZStack {
                HStack(spacing: 0) {
                    // Shelf sidebar on the left — shown when isSidebarVisible is true.
                    // Uses a wrapper view to ensure re-renders on isSidebarVisible changes.
                    if let lm = layoutManager {
                        SidebarVisibleWrapper(layoutManager: lm)
                    }

                    VStack(spacing: 0) {
                    TerminalSplitTreeView(
                        tree: viewModel.surfaceTree,
                        action: { delegate?.performSplitAction($0) })
                        .environmentObject(ghostty)
                        .ghosttyLastFocusedSurface(lastFocusedSurface)
                        .focused($focused)
                        .onAppear { self.focused = true }
                        .onChange(of: focusedSurface) { newValue in
                            // We want to keep track of our last focused surface so even if
                            // we lose focus we keep this set to the last non-nil value.
                            if newValue != nil {
                                lastFocusedSurface = .init(newValue)
                                self.delegate?.focusedSurfaceDidChange(to: newValue)
                            }
                        }
                        .onChange(of: pwdURL) { newValue in
                            self.delegate?.pwdDidChange(to: newValue)
                        }
                        .onChange(of: cellSize) { newValue in
                            guard let size = newValue else { return }
                            self.delegate?.cellSizeDidChange(to: size)
                        }
                        .frame(idealWidth: lastFocusedSurface?.value?.initialSize?.width,
                               idealHeight: lastFocusedSurface?.value?.initialSize?.height)
                    }
                    // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                    .ignoresSafeArea(.container, edges: ghostty.config.macosTitlebarStyle == .hidden ? .top : [])
                }

                // Overlay sidebar (floating, no terminal resize) when sidebar is hidden
                // and mouse is hovering the left edge.
                if let lm = layoutManager {
                    SidebarOverlayWrapper(layoutManager: lm)
                }

                if let surfaceView = lastFocusedSurface?.value {
                    TerminalCommandPaletteView(
                        surfaceView: surfaceView,
                        isPresented: $viewModel.commandPaletteIsShowing,
                        ghosttyConfig: ghostty.config,
                        updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel) { action in
                        self.delegate?.performAction(action, on: surfaceView)
                    }
                }

                // Show update information above all else.
                if viewModel.updateOverlayIsVisible {
                    UpdateOverlay()
                }
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }
}

// MARK: - Sidebar Wrapper Views

/// Shows the permanent sidebar when isSidebarVisible is true.
/// Separate view so @ObservedObject observation is scoped here.
private struct SidebarVisibleWrapper: View {
    @ObservedObject var layoutManager: AppLayoutManager

    var body: some View {
        if layoutManager.isSidebarVisible {
            SurfaceShelfView(layoutManager: layoutManager)
                .transition(.move(edge: .leading).combined(with: .opacity))
            Divider()
        }
    }
}

/// Shows the floating overlay sidebar and edge hover strip when isSidebarVisible is false.
private struct SidebarOverlayWrapper: View {
    @ObservedObject var layoutManager: AppLayoutManager

    var body: some View {
        if !layoutManager.isSidebarVisible {
            ZStack(alignment: .leading) {
                if layoutManager.isSidebarOverlaying {
                    HStack(spacing: 0) {
                        SurfaceShelfView(layoutManager: layoutManager)
                            .shadow(radius: 8, x: 4, y: 0)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Spacer()
                    }
                }

                HStack {
                    SidebarEdgeHoverStrip(isHovering: Binding(
                        get: { layoutManager.isSidebarOverlaying },
                        set: { newVal in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                layoutManager.isSidebarOverlaying = newVal
                            }
                        }
                    ))
                    // When the sidebar is showing, expand the strip to cover its full
                    // width so mouseExited only fires when the cursor truly leaves the
                    // sidebar. hitTest returns nil so clicks pass through to the sidebar.
                    .frame(width: layoutManager.isSidebarOverlaying ? 200 : 20)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugTitlebarButtonView: View {
    @State private var isPopover = false

    var body: some View {
        Button(action: { isPopover = true }) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Debug Build")
                    .font(.headline)
                Text("You're running a debug build of Phantom! Performance will be degraded.\n\nDebug builds are very slow and only recommended during development.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 280)
        }
        .accessibilityLabel("Debug build warning")
    }
}
