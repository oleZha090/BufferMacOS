import AppKit
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
            if code == "ru" { return .russian }
            if code == "en" { return .english }
        }
        return .english
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor var appearance: NSAppearance? {
        switch self {
        case .system: return nil // Inherit changes to the macOS appearance live.
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class PresentationPreferences: ObservableObject {
    static let languageKey = "interfaceLanguage"
    static let themeKey = "interfaceTheme"
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.languageKey) }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }
    private let defaults: UserDefaults
    private let bundle: Bundle

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        theme = defaults.string(forKey: Self.themeKey).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    var locale: Locale { Locale(identifier: language.resolved().rawValue) }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let code = language.resolved().rawValue
        let localizedBundle = bundle.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        let format = localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    func shortcutLabel(_ configuration: HotkeyConfiguration) -> String {
        guard configuration.keyLabel == "Space" else { return configuration.display }
        return String(configuration.display.dropLast(5)) + text("Space")
    }

    func hotkeyError(_ error: Error) -> String {
        switch error {
        case HotkeyError.invalid:
            return text("Use Command, Option or Control together with a non-modifier key.")
        case HotkeyError.registration(let code):
            return text("This shortcut could not be registered (%d). It may be in use by macOS or another app. Choose another shortcut.", Int(code))
        default:
            return text("Could not save the shortcut (%d). Try again.", (error as NSError).code)
        }
    }
}
