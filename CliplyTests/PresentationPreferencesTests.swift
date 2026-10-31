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
        XCTAssertEqual(preferences.hotkeyError(error), "Не удалось зарегистрировать сочетание (-9878). Возможно, оно занято macOS или другим приложением. Выберите другое.")
        XCTAssertEqual(preferences.shortcutLabel(shortcut), "⌘Пробел")
        preferences.language = .english
        XCTAssertEqual(preferences.hotkeyError(error), "This shortcut could not be registered (-9878). It may be in use by macOS or another app. Choose another shortcut.")
        XCTAssertEqual(preferences.shortcutLabel(shortcut), "⌘Space")
    }

    func testDiagnosticCodesKeepExactDigitsAndSignInBothLanguages() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PresentationPreferences(defaults: defaults)
        for language in [AppLanguage.russian, .english] {
            preferences.language = language
            for code in [Int32.min, -9878, 0, Int32.max] {
                let message = preferences.hotkeyError(HotkeyError.registration(code))
                XCTAssertTrue(message.contains("(\(code))"), message)
            }
            // NSError uses a platform-sized Int, which must not be truncated to printf's %d.
            for code in [Int.min, -1234567, 1234567, Int.max] {
                let message = preferences.hotkeyError(NSError(domain: "CliplyTests", code: code))
                XCTAssertTrue(message.contains("(\(code))"), message)
            }
            let loginError = preferences.text("Launch at Login could not be updated (%@). Try again in System Settings.", String(-1234567))
            XCTAssertTrue(loginError.contains("(-1234567)"), loginError)
        }
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
