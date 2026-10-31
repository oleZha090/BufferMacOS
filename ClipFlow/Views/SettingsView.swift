import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @ObservedObject var login: LaunchAtLoginService
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject var history: ClipboardHistoryService
    let clearHistory: () -> Void

    var body: some View {
        TabView {
            Form {
                Section("Startup") {
                    Toggle("Launch at Login", isOn: Binding(get: { login.isEnabled || login.needsApproval }, set: login.setEnabled))
                    LabeledContent("Status", value: login.statusLabel)
                    if login.needsApproval { Button("Open Login Items Settings", action: login.openSettings) }
                    if let message = login.errorMessage { Text(message).foregroundStyle(.red) }
                }
                Section("Clipboard") {
                    LabeledContent("History", value: "\(history.items.count) / 10 items")
                    Button("Clear History", role: .destructive, action: clearHistory).disabled(history.items.isEmpty)
                    Text("Clearing history leaves the system clipboard unchanged.").font(.caption).foregroundStyle(.secondary)
                }
                Section { LabeledContent("ClipFlow", value: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")") }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Open Clipboard Shortcut") {
                    ShortcutRecorderView(configuration: model.shortcut, onRecord: model.updateShortcut,
                                         onBegin: model.beginRecording, onEnd: model.finishRecording).frame(height: 32)
                    Text("Click to record. Use Command, Option or Control with a key; Shift is also supported.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reset to Default", action: model.resetShortcut)
                    if let error = model.shortcutError { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Text("In history: use ↑ / ↓ to select, Return to paste, Escape to close. Start typing to search.")
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Keyboard", systemImage: "keyboard") }

            Form {
                Section("Private by design") {
                    Text("The last 10 text items live only in this process's memory. ClipFlow does not save history to disk, send it over the network, or collect analytics.")
                    Text("History disappears when ClipFlow quits. This does not guarantee physical erasure from system memory or swap.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Items marked concealed or transient by their source app are ignored. History stores text up to 100 KB; images and files are not collected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Automatic paste") {
                    LabeledContent("Accessibility", value: accessibility.isTrusted ? "Allowed" : "Not allowed")
                    Text("Accessibility allows ClipFlow to restore focus and send a single ⌘V to the app you were using. History and the global shortcut work without this permission.")
                    HStack {
                        Button("Request Permission", action: accessibility.requestPermission)
                        Button("Open System Settings", action: accessibility.openSettings)
                    }
                    Text("Without permission, select an item and paste manually with ⌘V.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Clear History", role: .destructive, action: clearHistory).disabled(history.items.isEmpty)
            }
            .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 540, height: 500)
    }
}
