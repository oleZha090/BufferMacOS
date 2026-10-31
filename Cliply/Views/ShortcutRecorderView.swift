import AppKit
import SwiftUI

@MainActor
struct ShortcutRecorderView: NSViewRepresentable {
    let configuration: HotkeyConfiguration
    @ObservedObject var preferences: PresentationPreferences
    let onRecord: (HotkeyConfiguration) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.configuration = configuration
        button.recordingTitle = preferences.text("Press shortcut… (Esc to cancel)")
        button.recordingAccessibilityLabel = preferences.text("Press a shortcut. Escape cancels.")
        button.shortcutTitle = preferences.shortcutLabel(configuration)
        button.shortcutAccessibilityLabel = preferences.text("Record shortcut, currently %@", preferences.shortcutLabel(configuration))
        button.onRecord = onRecord
        button.onBegin = onBegin
        button.onEnd = onEnd
        button.updateTitle()
    }
}

final class ShortcutRecorderButton: NSButton {
    var configuration = HotkeyConfiguration.standard
    var recordingTitle = ""
    var recordingAccessibilityLabel = ""
    var shortcutTitle = ""
    var shortcutAccessibilityLabel = ""
    var onRecord: ((HotkeyConfiguration) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    private var recording = false
    private var windowObservers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { true }

    func updateTitle() {
        title = recording ? recordingTitle : shortcutTitle
        setAccessibilityLabel(recording ? recordingAccessibilityLabel : shortcutAccessibilityLabel)
    }

    @objc func startRecording() {
        guard !recording else { return }
        recording = true
        onBegin?()
        guard window?.makeFirstResponder(self) == true else { finish(); return }
        updateTitle()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let candidate = HotkeyConfiguration(event: event)
        onRecord?(candidate)
        finish()
    }

    private func finish() {
        guard recording else { return }
        recording = false
        onEnd?()
        updateTitle()
    }

    override func resignFirstResponder() -> Bool {
        finish()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        finish()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            })
        }
    }

    deinit { for observer in windowObservers { NotificationCenter.default.removeObserver(observer) } }
}
