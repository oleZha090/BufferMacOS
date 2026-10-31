import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refresh() { isTrusted = AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func enableAutomaticPaste() {
        requestPermission()
        if !isTrusted { openSettings() }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
