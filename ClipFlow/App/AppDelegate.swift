import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = ClipboardHistoryService()
    private let hotkeys = HotkeyManager()
    private let accessibility = AccessibilityService()
    private let login = LaunchAtLoginService()
    private var monitor: ClipboardMonitor!
    private var pasteService: ClipboardPasteService!
    private var settings: SettingsViewModel!
    private var viewModel: ClipboardViewModel!
    private var windows: WindowManager!
    private var statusItem: NSStatusItem!
    private var target: NativePasteTarget?
    private var observers: [NSObjectProtocol] = []
    private var pasteTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted XCTest loads the executable without starting background integrations.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        monitor = ClipboardMonitor(history: history)
        pasteService = ClipboardPasteService(clipboard: monitor, environment: NativePasteEnvironment())
        settings = SettingsViewModel(hotkeys: hotkeys)
        viewModel = ClipboardViewModel(history: history)
        windows = WindowManager(model: viewModel, settings: settings, login: login, accessibility: accessibility)
        windows.onDismiss = { [weak self] in self?.target = nil }
        viewModel.onChoose = { [weak self] item in self?.choose(item) }
        viewModel.onClear = { [weak self] in self?.monitor.clearHistory() }
        hotkeys.onTrigger = { [weak self] in self?.toggleHistory() }
        installStatusItem()
        settings.registerSavedShortcut()
        monitor.start()
        observeLifecycle()
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipFlow")
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "ClipFlow — left click: history, right click: menu"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            windows.statusButtonWindow = button.window
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            windows.dismiss()
            showMenu()
        } else { toggleHistory() }
    }

    private func toggleHistory() {
        guard !viewModel.isProcessing else { return }
        if windows.isVisible { windows.dismiss(); return }
        let point = NSEvent.mouseLocation
        // Capture before the panel is made key. Never update this while using ClipFlow UI.
        target = NativePasteTarget.capture()
        accessibility.refresh()
        monitor.pollNow()
        windows.show(near: point)
    }

    private func choose(_ item: ClipboardItem) {
        guard !viewModel.isProcessing else { return }
        viewModel.isProcessing = true // Synchronous guard against double clicks / repeating Return.
        let originalTarget = target
        pasteTask = Task { [weak self] in
            guard let self else { return }
            let result = await pasteService.paste(item.text, to: originalTarget) { [weak self] in self?.windows.dismiss() }
            viewModel.isProcessing = false
            switch result {
            case .manual(let message): windows.showHint(message)
            case .clipboardFailure:
                viewModel.errorMessage = "Could not update the system clipboard. Your history entry is preserved. Try again."
                if !windows.isVisible { windows.showHint("Could not copy the selected text. The history entry is preserved.") }
            case .posted, .ignored: break
            }
            pasteTask = nil
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Clipboard History", action: #selector(openHistory)))
        menu.addItem(item("Settings…", action: #selector(openSettings)))
        let clear = item("Clear History", action: #selector(clearHistory))
        clear.isEnabled = !history.items.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())
        login.refresh()
        let startup = item("Launch at Login", action: #selector(toggleLogin))
        startup.state = login.isEnabled ? .on : (login.needsApproval ? .mixed : .off)
        menu.addItem(startup)
        menu.addItem(.separator())
        menu.addItem(item("Quit ClipFlow", action: #selector(quit)))
        menu.autoenablesItems = false
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openHistory() {
        // Run after NSMenu has closed its tracking loop.
        DispatchQueue.main.async { [weak self] in self?.toggleHistory() }
    }
    @objc private func openSettings() { windows.showSettings() }
    @objc private func clearHistory() { monitor.clearHistory() }
    @objc private func toggleLogin() {
        login.setEnabled(!(login.isEnabled || login.needsApproval))
        if login.errorMessage != nil || login.needsApproval { windows.showSettings() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func installEditMenu() {
        // Standard responder-chain actions keep Cmd+A/C/V/X working in the search field.
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "ClipFlow", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "ClipFlow")
        let settingsItem = item("Settings…", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        appMenu.addItem(settingsItem)
        let quitItem = item("Quit ClipFlow", action: #selector(quit))
        quitItem.keyEquivalent = "q"
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        let actions: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, selector, key) in actions { edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key)) }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor.stop(); self?.windows.dismiss() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor.pollNow(); self?.monitor.start() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibility.refresh(); self?.login.refresh() }
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        pasteTask?.cancel()
        monitor?.stop()
        hotkeys.unregister()
        windows?.shutdown()
        history.clear()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
