import SwiftUI

// Catppuccin Mocha Mauve
private let mauveAccent = Color(red: 203/255, green: 166/255, blue: 247/255)

struct SurfaceShelfView: View {
    @ObservedObject var layoutManager: AppLayoutManager

    private var terminalBackground: Color {
        layoutManager.sidebarItems.first?.surface.derivedConfig.backgroundColor
            ?? Color(NSColor.windowBackgroundColor)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(layoutManager.sidebarItems) { item in
                    SidebarItemRow(item: item, layoutManager: layoutManager)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .frame(width: 200)
        .background(terminalBackground)
        .onHover { hovering in
            if !hovering {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layoutManager.isSidebarOverlaying = false
                }
            }
        }
    }
}

private struct SidebarItemRow: View {
    let item: SidebarItem
    @ObservedObject var layoutManager: AppLayoutManager
    @ObservedObject private var surface: Ghostty.SurfaceView

    @State private var isHovered = false

    init(item: SidebarItem, layoutManager: AppLayoutManager) {
        self.item = item
        self.layoutManager = layoutManager
        self._surface = ObservedObject(wrappedValue: item.surface)
    }

    /// Last path component of pwd, falling back to "~" for home or unknown.
    private var dirName: String {
        guard let pwd = surface.pwd, !pwd.isEmpty else { return "~" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if pwd == home { return "~" }
        return URL(fileURLWithPath: pwd).lastPathComponent
    }

    /// Shell title shown as subtitle when it carries meaningful info (not just "zsh" or empty).
    private var subtitle: String? {
        let title = surface.title
        guard !title.isEmpty else { return nil }
        let boring = ["zsh", "bash", "fish", "sh"]
        guard !boring.contains(title.lowercased()) else { return nil }
        return title
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dirName)
                    .font(.system(size: 12))
                    .foregroundStyle(item.state == .focused ? mauveAccent : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(item.state == .shelved ? 0.55 : 1.0)

                Text(subtitle ?? " ")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(subtitle == nil ? 0 : 1)
            }

            Spacer(minLength: 0)

            if isHovered && canClose {
                Button(action: { closeItem() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if item.state == .shelved && item.hasActivity {
                TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                    let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                    let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % frames.count
                    Text(frames[idx])
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.green)
                }
            } else if item.state == .shelved && item.needsAttention {
                Text("●")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .overlay(alignment: .leading) {
            if item.state != .shelved {
                RoundedRectangle(cornerRadius: 2)
                    .fill(item.state == .focused ? mauveAccent : mauveAccent.opacity(0.3))
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .draggable(item.surface)
        .onTapGesture {
            switch item.state {
            case .focused:
                break
            case .active:
                layoutManager.focusActiveSurface(item.surface)
            case .shelved:
                layoutManager.unshelveAsSole(item.shelvedSurface!)
            }
        }
    }

    /// False only when this is the last panel everywhere (can't close the final surface).
    private var canClose: Bool {
        let activeCount = layoutManager.sidebarItems.filter { $0.state != .shelved }.count
        let shelvedCount = layoutManager.shelvedSurfaces.count
        if item.state == .shelved { return true }
        return activeCount > 1 || shelvedCount > 0
    }

    private func closeItem() {
        switch item.state {
        case .shelved:
            layoutManager.close(item.shelvedSurface!)
        case .focused, .active:
            layoutManager.closeActive(item.surface)
        }
    }

    private var rowBackground: Color {
        if item.state == .focused {
            return mauveAccent.opacity(0.15)
        }
        return isHovered
            ? mauveAccent.opacity(0.1)
            : Color.clear
    }
}
