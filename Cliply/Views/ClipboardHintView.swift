import SwiftUI

@MainActor
struct ClipboardHintView: View {
    let message: String
    @ObservedObject var preferences: PresentationPreferences
    @ObservedObject var accessibility: AccessibilityService
    let openSettings: () -> Void
    let enableAutomaticPaste: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cliply", systemImage: "clipboard").font(.headline)
            Text(preferences.text(message)).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                if accessibility.isTrusted {
                    Button(preferences.text("Settings"), action: openSettings)
                } else {
                    Button(preferences.text("Enable automatic paste"), action: enableAutomaticPaste)
                }
                Spacer()
                Button(preferences.text("Dismiss"), action: dismiss)
            }.buttonStyle(.borderless)
        }
        .padding(16).frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.locale, preferences.locale)
    }
}
