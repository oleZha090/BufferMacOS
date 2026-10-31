import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let selected: Bool
    let choose: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isURL ? "link" : "text.alignleft")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .frame(width: 22).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text).font(.system(size: 13)).lineLimit(3)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.copiedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paste: \(String(item.text.prefix(120)))")
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Remove from history").accessibilityLabel("Remove from history")
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
