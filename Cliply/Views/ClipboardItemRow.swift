import AppKit
import SwiftUI

@MainActor
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let selected: Bool
    @ObservedObject var preferences: PresentationPreferences
    let choose: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 10) {
                    if let image = item.image, let preview = NSImage(data: image.thumbnailPNG) {
                        Image(nsImage: preview).resizable().scaledToFit()
                            .frame(width: 80, height: 64)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: item.image != nil ? "photo" : (item.isURL ? "link" : "text.alignleft"))
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                            .frame(width: 22).padding(.top, 2)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let image = item.image {
                            Text(image.sourceName ?? preferences.text("Image"))
                                .font(.system(size: 13, weight: .medium)).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(preferences.text("%@ × %@ pixels", String(image.pixelWidth), String(image.pixelHeight)))
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let text = item.text {
                            Text(text).font(.system(size: 13)).lineLimit(3)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(item.copiedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pasteLabel)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help(preferences.text("Remove from history")).accessibilityLabel(preferences.text("Remove from history"))
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var pasteLabel: String {
        switch item.content {
        case .text(let text): return preferences.text("Paste: %@", String(text.prefix(120)))
        case .image(let image): return preferences.text("Paste image: %@ × %@ pixels", String(image.pixelWidth), String(image.pixelHeight))
        }
    }
}
