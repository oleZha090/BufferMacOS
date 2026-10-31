import SwiftUI

@MainActor
struct ClipboardPopupView: View {
    @ObservedObject var model: ClipboardViewModel
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject var preferences: PresentationPreferences
    let openSettings: () -> Void
    let enableAutomaticPaste: () -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "clipboard").font(.title3).foregroundStyle(Color.accentColor)
                Text("Cliply").font(.headline)
                Text("\(model.history.items.count) / 10").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.clearHistory(); searchFocused = true } label: { Image(systemName: "trash") }
                    .help(preferences.text("Clear History")).accessibilityLabel(preferences.text("Clear History"))
                    .disabled(model.history.items.isEmpty || model.isProcessing)
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help(preferences.text("Settings")).accessibilityLabel(preferences.text("Settings"))
                Button(action: close) { Image(systemName: "xmark") }
                    .help(preferences.text("Close · Esc")).accessibilityLabel(preferences.text("Close · Esc"))
            }
            .buttonStyle(.borderless)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(preferences.text("Search clipboard history"), text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel(preferences.text("Search clipboard history"))
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(preferences.text("Clear search"))
                }
            }
            .padding(10).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            if !accessibility.isTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label(preferences.text("To paste with Enter, allow Cliply to control your Mac. Without permission, Enter copies the selected item."), systemImage: "info.circle")
                    Button(preferences.text("Enable automatic paste"), action: enableAutomaticPaste)
                        .buttonStyle(.link).disabled(model.isProcessing)
                }
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = model.errorMessage {
                Text(preferences.text(message)).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text(preferences.text(model.query.isEmpty ? "Your clipboard, a little more useful" : "No matches"))
                        .font(.headline)
                    Text(preferences.text(model.query.isEmpty ? "Copy text or an image in any app. Your last 10 items will appear here." : "Try a different search."))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.items) { item in
                                ClipboardItemRow(item: item, selected: model.selectedID == item.id, preferences: preferences,
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
                Text(preferences.text(accessibility.isTrusted ? "↑ ↓  Select     ↩  Paste     esc  Close" : "↑ ↓  Select     ↩  Copy     esc  Close"))
                Spacer()
                Text(preferences.text("Only in memory")).foregroundStyle(.tertiary)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))
        .environment(\.locale, preferences.locale)
        .task(id: model.focusToken) {
            searchFocused = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
    }
}
