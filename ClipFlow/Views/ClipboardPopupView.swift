import SwiftUI

@MainActor
struct ClipboardPopupView: View {
    @ObservedObject var model: ClipboardViewModel
    @ObservedObject var accessibility: AccessibilityService
    let openSettings: () -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "clipboard").font(.title3).foregroundStyle(Color.accentColor)
                Text("ClipFlow").font(.headline)
                Text("\(model.history.items.count) / 10").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.clearHistory(); searchFocused = true } label: { Image(systemName: "trash") }
                    .help("Clear history").disabled(model.history.items.isEmpty || model.isProcessing)
                Button(action: openSettings) { Image(systemName: "gearshape") }.help("Settings")
                Button(action: close) { Image(systemName: "xmark") }.help("Close · Esc")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search clipboard history")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }
            .padding(10).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            if !accessibility.isTrusted {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("Select an item, then press ⌘V. Enable Accessibility in Settings for automatic paste.")
                    Spacer(minLength: 0)
                    Button("Settings", action: openSettings).buttonStyle(.link)
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text(model.query.isEmpty ? "Your clipboard, a little more useful" : "No matches")
                        .font(.headline)
                    Text(model.query.isEmpty ? "Copy some text in any app. Your last 10 items will appear here." : "Try a different search.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.items) { item in
                                ClipboardItemRow(item: item, selected: model.selectedID == item.id,
                                                 choose: { model.choose(item) }, remove: { model.remove(item); searchFocused = true })
                                    .id(item.id)
                            }
                        }
                        .padding(1)
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
                .disabled(model.isProcessing)
            }

            HStack {
                Text("↑ ↓  Select     ↩  Paste     esc  Close")
                Spacer()
                Text("Only in memory").foregroundStyle(.tertiary)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))
        .task(id: model.focusToken) {
            searchFocused = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
    }
}
