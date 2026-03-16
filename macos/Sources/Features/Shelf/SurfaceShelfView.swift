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
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct ShelvedItemRow: View {
    let shelved: ShelvedSurface
    @ObservedObject var layoutManager: AppLayoutManager

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(shelved.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if shelved.hasActivity {
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 6, height: 6)
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
        .onTapGesture {
            layoutManager.unshelve(shelved)
        }
    }
}
