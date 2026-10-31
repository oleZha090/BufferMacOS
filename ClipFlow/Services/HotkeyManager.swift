import Carbon
import Foundation

@MainActor
protocol HotkeyRegistering: AnyObject {
    func register(_ configuration: HotkeyConfiguration) throws
    func unregister()
}

enum HotkeyError: LocalizedError {
    case invalid
    case registration(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalid: return "Use Command, Option or Control together with a non-modifier key."
        case .registration(let code): return "This shortcut could not be registered (\(code)). It may be in use by macOS or another app. Choose another shortcut."
        }
    }
}

@MainActor
final class HotkeyManager: HotkeyRegistering {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 0
    private var activeID: UInt32 = 0
    private var configuration: HotkeyConfiguration?
    var onTrigger: (() -> Void)?
    private static let signature: OSType = 0x434C5046 // CLPF

    private func installHandler() throws {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers application events on the main run loop.
            MainActor.assumeIsolated {
                if identifier.signature == HotkeyManager.signature && identifier.id == manager.activeID {
                    manager.onTrigger?()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw HotkeyError.registration(status) }
    }

    func register(_ configuration: HotkeyConfiguration) throws {
        guard configuration.isValid else { throw HotkeyError.invalid }
        guard self.configuration != configuration || hotkey == nil else { return }
        try installHandler()
        nextID &+= 1
        var candidate: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: nextID)
        let status = RegisterEventHotKey(configuration.keyCode, configuration.modifiers, id, GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { throw HotkeyError.registration(status) }
        // Keep the old shortcut working until the replacement is registered successfully.
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = candidate
        activeID = nextID
        self.configuration = configuration
    }

    func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        activeID = 0
        configuration = nil
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
