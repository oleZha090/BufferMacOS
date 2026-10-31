import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @ObservedObject var login: LaunchAtLoginService
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject var history: ClipboardHistoryService
    @ObservedObject var preferences: PresentationPreferences
    let clearHistory: () -> Void

    var body: some View {
        TabView {
            Form {
                Section(preferences.text("Interface")) {
                    Picker(preferences.text("Language"), selection: $preferences.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(preferences.text(language.titleKey)).tag(language)
                        }
                    }
                    Picker(preferences.text("Appearance"), selection: $preferences.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(preferences.text(theme.titleKey)).tag(theme)
                        }
                    }
                    Text(preferences.text("Language and appearance changes apply immediately."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(preferences.text("Startup")) {
                    Toggle(preferences.text("Launch at Login"), isOn: Binding(get: { login.isEnabled || login.needsApproval }, set: login.setEnabled))
                    LabeledContent(preferences.text("Status"), value: preferences.text(login.statusLabel))
                    if login.needsApproval { Button(preferences.text("Open Login Items Settings"), action: login.openSettings) }
                    if let code = login.errorCode {
                        Text(preferences.text("Launch at Login could not be updated (%d). Try again in System Settings.", code)).foregroundStyle(.red)
                    }
                }
                Section(preferences.text("Clipboard")) {
                    LabeledContent(preferences.text("History"), value: preferences.text("%d / 10 items", history.items.count))
                    Button(preferences.text("Clear History"), role: .destructive, action: clearHistory).disabled(history.items.isEmpty)
                    Text(preferences.text("Clearing history leaves the system clipboard unchanged.")).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Cliply", value: preferences.text("Version %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                }
            }
            .tabItem { Label(preferences.text("General"), systemImage: "gearshape") }

            Form {
                Section(preferences.text("Open Clipboard Shortcut")) {
                    ShortcutRecorderView(configuration: model.shortcut, preferences: preferences, onRecord: model.updateShortcut,
                                         onBegin: model.beginRecording, onEnd: model.finishRecording).frame(height: 32)
                    Text(preferences.text("Click to record. Use Command, Option or Control with a key; Shift is also supported."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(preferences.text("Reset to Default"), action: model.resetShortcut)
                    if let error = model.shortcutError { Text(preferences.hotkeyError(error)).foregroundStyle(.red) }
                }
                Section {
                    Text(preferences.text("In history: use ↑ / ↓ to select, Return to paste, Escape to close. Start typing to search."))
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label(preferences.text("Keyboard"), systemImage: "keyboard") }

            Form {
                Section(preferences.text("Private by design")) {
                    Text(preferences.text("The last 10 text items live only in this process's memory. Cliply does not save history to disk, send it over the network, or collect analytics."))
                    Text(preferences.text("History disappears when Cliply quits. This does not guarantee physical erasure from system memory or swap."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(preferences.text("Items marked concealed or transient by their source app are ignored. History stores text up to 100 KB; images and files are not collected."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(preferences.text("Automatic paste")) {
                    LabeledContent(preferences.text("Accessibility"), value: preferences.text(accessibility.isTrusted ? "Allowed" : "Not allowed"))
                    Text(preferences.text("Accessibility allows Cliply to restore focus and send a single ⌘V to the app you were using. History and the global shortcut work without this permission."))
                    HStack {
                        Button(preferences.text("Request Permission"), action: accessibility.requestPermission)
                        Button(preferences.text("Open System Settings"), action: accessibility.openSettings)
                    }
                    Text(preferences.text("Without permission, select an item and paste manually with ⌘V."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(preferences.text("Clear History"), role: .destructive, action: clearHistory).disabled(history.items.isEmpty)
            }
            .tabItem { Label(preferences.text("Privacy"), systemImage: "hand.raised") }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 560)
        .environment(\.locale, preferences.locale)
    }
}
