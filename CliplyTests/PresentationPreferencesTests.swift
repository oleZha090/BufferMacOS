import AppKit
import Carbon
import XCTest
@testable import Cliply

@MainActor
final class PresentationPreferencesTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "CliplyPresentationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testDefaultsFollowSystemAndInvalidSettingsFallBack() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = PresentationPreferences(defaults: defaults)
        XCTAssertEqual(fresh.language, .system)
        XCTAssertEqual(fresh.theme, .system)
        defaults.set("unknown", forKey: PresentationPreferences.languageKey)
        defaults.set("unknown", forKey: PresentationPreferences.themeKey)
        let recovered = PresentationPreferences(defaults: defaults)
        XCTAssertEqual(recovered.language, .system)
        XCTAssertEqual(recovered.theme, .system)
    }

    func testSelectedLanguageAndThemePersistBetweenInstances() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PresentationPreferences(defaults: defaults)
        preferences.language = .russian
        preferences.theme = .dark
        let restored = PresentationPreferences(defaults: defaults)
        XCTAssertEqual(restored.language, .russian)
        XCTAssertEqual(restored.theme, .dark)
        XCTAssertEqual(restored.locale.language.languageCode?.identifier, "ru")
        restored.language = .english
        restored.theme = .light
        let updated = PresentationPreferences(defaults: defaults)
        XCTAssertEqual(updated.language, .english)
        XCTAssertEqual(updated.theme, .light)
    }

    func testSystemLanguageResolvesAvailableTranslationsInPreferenceOrder() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ru-RU", "en-US"]), .russian)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "ru"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["de-DE", "ru_RU"]), .russian)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["ru"]), .english)
    }

    func testResourcesAreBundledAndLanguageChangesApplyWithoutRecreation() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNotNil(Bundle.main.path(forResource: "en", ofType: "lproj"))
        XCTAssertNotNil(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let preferences = PresentationPreferences(defaults: defaults)
        preferences.language = .russian
        XCTAssertEqual(preferences.text("Settings"), "Настройки")
        XCTAssertEqual(preferences.text("Appearance"), "Оформление")
        XCTAssertEqual(preferences.text("%d / 10 items", 7), "Записей: 7 / 10")
        XCTAssertEqual(preferences.text("Paste: %@", "100%\n🌍"), "Вставить: 100%\n🌍")
        preferences.language = .english
        XCTAssertEqual(preferences.text("Settings"), "Settings")
        XCTAssertEqual(preferences.text("%d / 10 items", 7), "7 / 10 items")
        XCTAssertEqual(preferences.text("Missing key"), "Missing key")
    }

    func testErrorsAndShortcutLabelsUseTheCurrentLanguage() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PresentationPreferences(defaults: defaults)
        let error = HotkeyError.registration(-9878)
        let shortcut = HotkeyConfiguration(keyCode: 49, modifiers: UInt32(cmdKey), keyLabel: "Space")
        preferences.language = .russian
        XCTAssertTrue(preferences.hotkeyError(error).contains("Не удалось"))
        XCTAssertTrue(preferences.hotkeyError(error).contains("-9878"))
        XCTAssertEqual(preferences.shortcutLabel(shortcut), "⌘Пробел")
        preferences.language = .english
        XCTAssertTrue(preferences.hotkeyError(error).contains("could not be registered"))
        XCTAssertEqual(preferences.shortcutLabel(shortcut), "⌘Space")
    }

    func testExplicitThemesMapToNativeAppearancesAndSystemRemovesOverride() {
        XCTAssertEqual(AppTheme.light.appearance?.name, .aqua)
        XCTAssertEqual(AppTheme.dark.appearance?.name, .darkAqua)
        XCTAssertNil(AppTheme.system.appearance)
    }

    func testAppNameAndCompiledIconAreBundledForFinderAndInstallation() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Cliply")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        let path = try XCTUnwrap(Bundle.main.path(forResource: "AppIcon", ofType: "icns"))
        XCTAssertNotNil(NSImage(contentsOfFile: path))
    }
}
