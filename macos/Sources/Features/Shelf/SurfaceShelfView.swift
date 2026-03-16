import SwiftUI

struct SurfaceShelfView: View {
    @ObservedObject var layoutManager: AppLayoutManager

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
        .background(.ultraThinMaterial)
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

    private var subtitle: String? {
        let title = surface.title
        guard !title.isEmpty else { return nil }
        if item.hasActivity { return title }
        guard title != item.displayName else { return nil }
        return title
    }

    var body: some View {
        HStack(spacing: 8) {
            // State dot
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(item.state == .shelved ? 0.55 : 1.0)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            // Right-side indicators (only for shelved items)
            if item.state == .shelved {
                if isHovered {
                    Button(action: { layoutManager.close(item.shelvedSurface!) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if item.hasActivity {
                    TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                        let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % frames.count
                        Text(frames[idx])
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                } else if item.needsAttention {
                    Text("●")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
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

    private var dotColor: Color {
        switch item.state {
        case .focused: return Color.accentColor
        case .active:  return Color.accentColor.opacity(0.4)
        case .shelved: return Color.clear
        }
    }

    private var rowBackground: Color {
        if item.state == .focused {
            return Color.accentColor.opacity(0.15)
        }
        return isHovered
            ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
            : Color.clear
    }
}
