import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    static let shortcutKey = "openClipboardShortcut"
    @Published private(set) var shortcut: HotkeyConfiguration
    @Published private(set) var shortcutError: String?
    private let defaults: UserDefaults
    private let hotkeys: HotkeyRegistering

    init(hotkeys: HotkeyRegistering, defaults: UserDefaults = .standard) {
        self.hotkeys = hotkeys
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.shortcutKey),
           let value = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data), value.isValid {
            shortcut = value
        } else { shortcut = .standard }
    }

    func registerSavedShortcut() {
        do { try hotkeys.register(shortcut); shortcutError = nil }
        catch { shortcutError = error.localizedDescription }
    }

    func updateShortcut(_ candidate: HotkeyConfiguration) {
        guard candidate != shortcut else { registerSavedShortcut(); return }
        do {
            guard candidate.isValid else { throw HotkeyError.invalid }
            try hotkeys.register(candidate)
            shortcut = candidate
            defaults.set(try JSONEncoder().encode(candidate), forKey: Self.shortcutKey)
            shortcutError = nil
        } catch { shortcutError = error.localizedDescription }
    }

    func resetShortcut() { updateShortcut(.standard) }

    func beginRecording() { shortcutError = nil; hotkeys.unregister() }
    func finishRecording() {
        let recordingError = shortcutError
        registerSavedShortcut()
        if shortcutError == nil { shortcutError = recordingError }
    }
}
