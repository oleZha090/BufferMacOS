import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    let panel = ClipboardPanel()
    private let model: ClipboardViewModel
    private let preferences: PresentationPreferences
    private let accessibility: AccessibilityService
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var settingsWindow: NSWindow?
    private var hintPanel: NSPanel?
    private var hintTask: Task<Void, Never>?
    private var isDismissing = false
    var onDismiss: (() -> Void)?
    weak var statusButtonWindow: NSWindow?

    init(model: ClipboardViewModel, settings: SettingsViewModel, login: LaunchAtLoginService, accessibility: AccessibilityService,
         preferences: PresentationPreferences) {
        self.model = model
        self.preferences = preferences
        self.accessibility = accessibility
        super.init()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ClipboardPopupView(model: model, accessibility: accessibility, preferences: preferences,
            openSettings: { [weak self] in self?.showSettings() },
            enableAutomaticPaste: { [weak self] in self?.enableAutomaticPaste() }, close: { [weak self] in self?.dismiss() }))
        let settingsWindow = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.isRestorable = false
        settingsWindow.contentView = NSHostingView(rootView: SettingsView(model: settings, login: login, accessibility: accessibility, history: model.history, preferences: preferences,
                                                                        clearHistory: { [weak model] in model?.clearHistory() }))
        settingsWindow.setContentSize(NSSize(width: 560, height: 560))
        self.settingsWindow = settingsWindow
        refreshLocalization()
    }

    func refreshLocalization() {
        panel.title = preferences.text("Cliply Clipboard History")
        panel.setAccessibilityLabel(panel.title)
        settingsWindow?.title = preferences.text("Cliply Settings")
    }

    var isVisible: Bool { panel.isVisible }

    func show(near point: NSPoint) {
        guard let screen = ScreenPositionHelper.screen(at: point) else { return }
        hideHint()
        model.prepareForOpen()
        panel.setFrame(ScreenPositionHelper.frame(near: point, size: NSSize(width: 500, height: 420), visibleFrame: screen.visibleFrame), display: false)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        removeMonitors()
        if wasVisible { onDismiss?() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { dismiss() }
    }

    func showSettings() {
        dismiss()
        guard let settingsWindow else { return }
        if !settingsWindow.isVisible { settingsWindow.center() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func enableAutomaticPaste() {
        dismiss()
        hideHint()
        accessibility.enableAutomaticPaste()
    }

    func showHint(_ message: String) {
        hideHint()
        guard let screen = ScreenPositionHelper.screen(at: NSEvent.mouseLocation) else { return }
        let hint = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hint.isReleasedWhenClosed = false
        hint.isOpaque = false
        hint.backgroundColor = .clear
        hint.level = .floating
        hint.hasShadow = true
        hint.hidesOnDeactivate = false
        hint.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hint.contentView = NSHostingView(rootView: ClipboardHintView(message: message, preferences: preferences, accessibility: accessibility,
            openSettings: { [weak self] in self?.hideHint(); self?.showSettings() },
            enableAutomaticPaste: { [weak self] in self?.enableAutomaticPaste() },
            dismiss: { [weak self] in self?.hideHint() }))
        hint.setFrame(ScreenPositionHelper.frame(near: NSEvent.mouseLocation, size: NSSize(width: 380, height: 200), visibleFrame: screen.visibleFrame), display: false)
        hint.orderFrontRegardless() // Does not activate Cliply or take focus away from the target.
        hintPanel = hint
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.hideHint()
        }
    }

    private func hideHint() { hintTask?.cancel(); hintTask = nil; hintPanel?.orderOut(nil); hintPanel = nil }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return event }
                if event.type != .keyDown {
                    if event.window !== self.panel && event.window !== self.statusButtonWindow { self.dismiss() }
                    return event
                }
                guard event.window === self.panel else { return event }
                // Let the input method finish composition before handling navigation or Return.
                if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                switch event.keyCode {
                case 125: self.model.move(1)
                case 126: self.model.move(-1)
                case 36, 76: self.model.choose()
                case 53: if !self.model.isProcessing { self.dismiss() }
                default: return event
                }
                return nil
            }
        }
        // Mouse-only observation does not require Accessibility or Input Monitoring.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    func shutdown() { dismiss(); hideHint(); settingsWindow?.orderOut(nil) }
}
