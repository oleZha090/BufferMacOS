import Carbon
import XCTest
@testable import ClipFlow

@MainActor
final class TestHotkeys: HotkeyRegistering {
    var configurations: [HotkeyConfiguration] = []
    var fails = false
    var unregisters = 0
    func register(_ configuration: HotkeyConfiguration) throws {
        if fails { throw HotkeyError.registration(OSStatus(eventHotKeyExistsErr)) }
        configurations.append(configuration)
    }
    func unregister() { unregisters += 1 }
}

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "ClipFlowTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testStandardAndModifierValidation() {
        XCTAssertTrue(HotkeyConfiguration.standard.isValid)
        XCTAssertEqual(HotkeyConfiguration.standard.display, "⇧⌘V")
        XCTAssertFalse(HotkeyConfiguration(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "⌘").isValid)
        XCTAssertFalse(HotkeyConfiguration(keyCode: 9, modifiers: 0, keyLabel: "V").isValid)
        XCTAssertFalse(HotkeyConfiguration(keyCode: 9, modifiers: UInt32(shiftKey), keyLabel: "V").isValid)
        XCTAssertFalse(HotkeyConfiguration(keyCode: 999, modifiers: UInt32(cmdKey), keyLabel: "V").isValid)
        XCTAssertFalse(HotkeyConfiguration(keyCode: 9, modifiers: UInt32(cmdKey) | 1, keyLabel: "V").isValid)
    }

    func testDefaultRegistrationAndSavedShortcutRestoration() {
        let defaults = makeDefaults()
        defer { defaults.removeObject(forKey: SettingsViewModel.shortcutKey) }
        let hotkeys = TestHotkeys()
        let model = SettingsViewModel(hotkeys: hotkeys, defaults: defaults)
        model.registerSavedShortcut()
        XCTAssertEqual(hotkeys.configurations, [.standard])
        let custom = HotkeyConfiguration(keyCode: 8, modifiers: UInt32(controlKey | optionKey), keyLabel: "C")
        model.updateShortcut(custom)
        XCTAssertEqual(model.shortcut, custom)
        let restored = SettingsViewModel(hotkeys: TestHotkeys(), defaults: defaults)
        XCTAssertEqual(restored.shortcut, custom)
        model.resetShortcut()
        XCTAssertEqual(model.shortcut, .standard)
    }

    func testConflictKeepsPreviousConfigurationAndReportsError() {
        let defaults = makeDefaults()
        defer { defaults.removeObject(forKey: SettingsViewModel.shortcutKey) }
        let hotkeys = TestHotkeys()
        let model = SettingsViewModel(hotkeys: hotkeys, defaults: defaults)
        hotkeys.fails = true
        model.updateShortcut(HotkeyConfiguration(keyCode: 8, modifiers: UInt32(cmdKey), keyLabel: "C"))
        XCTAssertEqual(model.shortcut, .standard)
        XCTAssertNotNil(model.shortcutError)
        XCTAssertNil(defaults.data(forKey: SettingsViewModel.shortcutKey))
    }

    func testInvalidShortcutNeverReachesRegistrarAndCorruptSettingFallsBack() {
        let defaults = makeDefaults()
        defaults.set(Data([0, 255]), forKey: SettingsViewModel.shortcutKey)
        defer { defaults.removeObject(forKey: SettingsViewModel.shortcutKey) }
        let hotkeys = TestHotkeys()
        let model = SettingsViewModel(hotkeys: hotkeys, defaults: defaults)
        XCTAssertEqual(model.shortcut, .standard)
        model.updateShortcut(HotkeyConfiguration(keyCode: 55, modifiers: 0, keyLabel: ""))
        XCTAssertNotNil(model.shortcutError)
        XCTAssertTrue(hotkeys.configurations.isEmpty)
        model.beginRecording(); model.finishRecording()
        XCTAssertEqual(hotkeys.unregisters, 1)
        XCTAssertEqual(hotkeys.configurations, [.standard])
    }

    func testNativeManagerRejectsInvalidConfigurationBeforeCarbonRegistration() {
        let manager = HotkeyManager()
        XCTAssertThrowsError(try manager.register(HotkeyConfiguration(keyCode: 55, modifiers: 0, keyLabel: "")))
        manager.unregister()
    }

    func testRecorderConflictIsStillVisibleAfterOldShortcutIsRestored() {
        let defaults = makeDefaults()
        let hotkeys = TestHotkeys()
        let model = SettingsViewModel(hotkeys: hotkeys, defaults: defaults)
        model.beginRecording()
        hotkeys.fails = true
        model.updateShortcut(HotkeyConfiguration(keyCode: 8, modifiers: UInt32(cmdKey), keyLabel: "C"))
        hotkeys.fails = false
        model.finishRecording()
        XCTAssertEqual(model.shortcut, .standard)
        XCTAssertNotNil(model.shortcutError)
        XCTAssertEqual(hotkeys.configurations.last, .standard)
    }
}
