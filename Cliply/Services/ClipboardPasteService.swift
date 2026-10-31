import AppKit
import ApplicationServices
import Carbon

@MainActor
protocol PasteTarget: AnyObject {
    var processIdentifier: Int32 { get }
    var isTerminated: Bool { get }
}

@MainActor
protocol PasteEnvironment: AnyObject {
    var canPostEvents: Bool { get }
    var frontmostPID: Int32? { get }
    var modifiersReleased: Bool { get }
    func activate(_ target: PasteTarget) -> Bool
    func restoreFocus(_ target: PasteTarget) -> Bool
    func postPaste(to target: PasteTarget) -> Bool
    func waitForNextCheck() async
}

@MainActor
final class NativePasteTarget: PasteTarget {
    let application: NSRunningApplication
    let focusedElement: AXUIElement?
    var processIdentifier: Int32 { application.processIdentifier }
    var isTerminated: Bool { application.isTerminated }

    init(application: NSRunningApplication) {
        self.application = application
        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.15)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                focusedElement = (value as! AXUIElement)
                AXUIElementSetMessagingTimeout(focusedElement!, 0.15)
            } else { focusedElement = nil }
        } else { focusedElement = nil }
    }

    static func capture() -> NativePasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return NativePasteTarget(application: app)
    }
}

@MainActor
final class NativePasteEnvironment: PasteEnvironment {
    var canPostEvents: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled()
    }
    var frontmostPID: Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var modifiersReleased: Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
    }

    func activate(_ target: PasteTarget) -> Bool {
        guard let target = target as? NativePasteTarget, !target.isTerminated else { return false }
        // A nonactivating history panel often leaves the original app active already.
        if target.application.isActive && frontmostPID == target.processIdentifier { return true }
        return target.application.activate(options: [])
    }

    func restoreFocus(_ target: PasteTarget) -> Bool {
        guard let target = target as? NativePasteTarget, frontmostPID == target.processIdentifier else { return false }
        guard let focused = target.focusedElement else { return true } // Apps may not expose AX text fields.
        if AXUIElementSetAttributeValue(focused, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return true }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var current: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &current) == .success,
              let current else { return false }
        return CFEqual(current, focused)
    }

    func postPaste(to target: PasteTarget) -> Bool {
        // Check again immediately before posting. Address the events to the captured process,
        // so an activation race cannot send Cmd+V to an unrelated application.
        guard canPostEvents, !target.isTerminated, frontmostPID == target.processIdentifier,
              modifiersReleased,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
        return true
    }

    func waitForNextCheck() async { try? await Task.sleep(for: .milliseconds(20)) }
}

enum PasteResult: Equatable {
    case posted
    case manual(String)
    case clipboardFailure
    case ignored
}

@MainActor
final class ClipboardPasteService {
    private let clipboard: ClipboardWriting
    private let environment: PasteEnvironment
    private(set) var isPasting = false

    init(clipboard: ClipboardWriting, environment: PasteEnvironment) {
        self.clipboard = clipboard
        self.environment = environment
    }

    func paste(_ text: String, to target: PasteTarget?, closePanel: () -> Void) async -> PasteResult {
        await paste(.text(text), to: target, closePanel: closePanel)
    }

    func paste(_ content: ClipboardContent, to target: PasteTarget?, closePanel: () -> Void) async -> PasteResult {
        guard !isPasting else { return .ignored }
        isPasting = true
        defer { isPasting = false }
        guard await clipboard.restore(content) else { return .clipboardFailure }
        closePanel()
        guard let target, !target.isTerminated else {
            return .manual("Item copied. Select a compatible field and press ⌘V.")
        }
        guard environment.activate(target) else {
            return .manual("Could not return to the original app. The item is ready for ⌘V.")
        }
        guard environment.canPostEvents else {
            return .manual("Item copied. Press ⌘V to paste. Enable Accessibility in Cliply Settings for automatic paste.")
        }

        // Confirmation, not an arbitrary delay: two observations of the original foreground
        // app, released physical modifiers, and a hard one-second deadline.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        var confirmations = 0
        for _ in 0..<50 {
            guard !Task.isCancelled, !target.isTerminated, ContinuousClock.now < deadline else { break }
            if environment.frontmostPID == target.processIdentifier && environment.modifiersReleased {
                confirmations += 1
                if confirmations >= 2 {
                    guard await clipboard.isRestoredContentCurrent(content) else {
                        return .manual("The clipboard changed before paste. The new clipboard was preserved; select your history item again to paste it.")
                    }
                    guard !Task.isCancelled, !target.isTerminated,
                          environment.frontmostPID == target.processIdentifier,
                          environment.restoreFocus(target), environment.frontmostPID == target.processIdentifier,
                          environment.postPaste(to: target) else {
                        return .manual("Automatic paste was unavailable. The item is ready for ⌘V.")
                    }
                    return .posted
                }
            } else { confirmations = 0 }
            await environment.waitForNextCheck()
        }
        return .manual("The original app did not regain focus. The item is ready for ⌘V.")
    }
}
