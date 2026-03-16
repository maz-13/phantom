import SwiftUI

struct SurfaceShelfView: View {
    @ObservedObject var layoutManager: AppLayoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(layoutManager.shelvedSurfaces) { shelved in
                        ShelvedItemRow(shelved: shelved, layoutManager: layoutManager)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
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

private struct ShelvedItemRow: View {
    let shelved: ShelvedSurface
    @ObservedObject var layoutManager: AppLayoutManager
    @ObservedObject private var surface: Ghostty.SurfaceView

    @State private var isHovered = false

    init(shelved: ShelvedSurface, layoutManager: AppLayoutManager) {
        self.shelved = shelved
        self.layoutManager = layoutManager
        self._surface = ObservedObject(wrappedValue: shelved.surface)
    }

    /// Shows as a subtitle when the live title differs from the display name.
    private var subtitle: String? {
        let title = surface.title
        guard !title.isEmpty, title != shelved.displayName else { return nil }
        return title
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(shelved.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if isHovered {
                Button(action: { layoutManager.close(shelved) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if shelved.hasActivity {
                TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                    let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                    let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % frames.count
                    Text(frames[idx])
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered
                      ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .draggable(shelved.surface)
        .onTapGesture {
            layoutManager.unshelveAsSole(shelved)
        }
    }
}
