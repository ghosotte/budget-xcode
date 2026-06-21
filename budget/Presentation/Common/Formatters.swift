import Foundation

/// Devise active de l'app, pilotée par le foyer courant. Source de vérité = UserDefaults
/// (`currencyCode`), poussée depuis AuthSession (foyer cloud) ou le foyer local par défaut.
enum Currency {
    static let storageKey = "currencyCode"
    static let `default` = "EUR"

    /// Codes ISO 4217 supportés — doit rester aligné avec `Household::SUPPORTED_CURRENCIES` côté backend.
    static let supported = ["EUR", "USD", "GBP", "CHF", "CAD", "JPY"]

    private static let symbols: [String: String] = [
        "EUR": "€", "USD": "$", "GBP": "£", "CHF": "CHF", "CAD": "$", "JPY": "¥",
    ]

    static func symbol(for code: String) -> String { symbols[code] ?? code }

    static func label(for code: String) -> String { "\(code) (\(symbol(for: code)))" }

    static var activeCode: String {
        UserDefaults.standard.string(forKey: storageKey) ?? `default`
    }

    static func setActive(_ code: String) {
        UserDefaults.standard.set(code, forKey: storageKey)
    }

    /// Devise déduite de la région système, ramenée aux codes supportés (repli `default`).
    static func systemDefault() -> String {
        let code = Locale.current.currency?.identifier ?? `default`
        return supported.contains(code) ? code : `default`
    }
}

/// Langue d'un foyer (catégories + libellés serveur). Codes alignés avec `Household::SUPPORTED_LOCALES`.
enum AppLocale {
    static let storageKey = "householdLocale"
    static let `default` = "fr"
    static let supported = ["fr", "en"]

    private static let labels: [String: String] = ["fr": "Français", "en": "English"]

    static func label(for code: String) -> String { labels[code] ?? code }

    /// Locale de formatage (dates, nombres) déduite de la langue active du foyer.
    /// On suit la langue, pas la région système : foyer en anglais → format US,
    /// foyer en français → format FR. Le symbole monétaire reste piloté par `Currency`.
    static var formattingLocale: Locale {
        switch activeCode {
        case "en": return Locale(identifier: "en_US")
        default:   return Locale(identifier: "fr_FR")
        }
    }

    /// Langue du foyer courant. Source de vérité = UserDefaults, poussée comme `Currency.setActive`.
    static var activeCode: String {
        UserDefaults.standard.string(forKey: storageKey) ?? `default`
    }

    static func setActive(_ code: String, caller: String = #function, file: String = #fileID, line: Int = #line) {
        let changed = code != activeCode
        print("🌐LANG setActive code=\(code) previousActive=\(activeCode) changed=\(changed) ← \(file):\(line) \(caller)")
        UserDefaults.standard.set(code, forKey: storageKey)
        BundleLanguage.set(code)
        if changed {
            NotificationCenter.default.post(name: BundleLanguage.didChange, object: nil)
        }
    }

    /// Langue système ramenée aux locales supportées (repli `default`).
    static func systemDefault() -> String {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return code.map { supported.contains($0) ? $0 : `default` } ?? `default`
    }
}

enum AmountFormatter {

    static var currencySymbol: String {
        Currency.symbol(for: Currency.activeCode)
    }

    /// Cache des formatters par couple (langue, précision). Reconstruit à la volée quand
    /// la langue du foyer change — on ne peut pas figer un `static let` puisque la locale varie.
    private static var cache: [String: NumberFormatter] = [:]

    private static func formatter(fractionDigits: Int) -> NumberFormatter {
        let key = "\(AppLocale.activeCode)|\(fractionDigits)"
        if let f = cache[key] { return f }
        let f = NumberFormatter()
        f.locale = AppLocale.formattingLocale
        f.numberStyle = .decimal
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        cache[key] = f
        return f
    }

    static func kpi(_ amount: Decimal, signed: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let text = formatter(fractionDigits: 0).string(from: number) ?? "0"
        let sign = signed && amount > 0 ? "+" : ""
        return "\(sign)\(text) \(currencySymbol)"
    }

    static func full(_ amount: Decimal, signed: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let text = formatter(fractionDigits: 2).string(from: number) ?? "0"
        let sign = signed && amount > 0 ? "+" : ""
        return "\(sign)\(text) \(currencySymbol)"
    }
}

enum AppDateFormatter {

    /// Cache des formatters par couple (langue, format). Reconstruit à la volée quand la
    /// langue du foyer change : les noms de mois / jours suivent alors la langue active.
    private static var cache: [String: DateFormatter] = [:]

    private static func formatter(_ format: String) -> DateFormatter {
        let key = "\(AppLocale.activeCode)|\(format)"
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = AppLocale.formattingLocale
        f.dateFormat = format
        cache[key] = f
        return f
    }

    static func dayMonth(_ date: Date) -> String {
        formatter("dd/MM").string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        formatter("LLLL yyyy").string(from: date).capitalized
    }

    static func daySection(_ date: Date) -> String {
        formatter("EEEE d MMMM").string(from: date).capitalized
    }
}
