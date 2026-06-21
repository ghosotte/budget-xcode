import Foundation
import Observation

/// Override de la langue de l'app indépendamment de la langue système.
///
/// La langue suit le foyer **actif** (`AppLocale.activeCode`), pas iOS. On y parvient en
/// remplaçant la classe de `Bundle.main` : toute résolution de chaîne (`Text`,
/// `NSLocalizedString`, `String(localized:)`) passe alors par le `.lproj` de la langue choisie.
private var bundleLanguageKey: UInt8 = 0

final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table: String?) -> String {
        guard let path = objc_getAssociatedObject(self, &bundleLanguageKey) as? String,
              let bundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: table)
        }
        return bundle.localizedString(forKey: key, value: value, table: table)
    }
}

enum BundleLanguage {
    /// Notification postée à chaque changement de langue (déclenche le re-render SwiftUI).
    static let didChange = Notification.Name("BundleLanguageDidChange")

    /// Bascule la résolution de chaînes vers la langue donnée. Repli sur le bundle système
    /// si le `.lproj` est absent (langue non embarquée).
    static func set(_ code: String) {
        object_setClass(Bundle.main, LocalizedBundle.self)
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
        objc_setAssociatedObject(Bundle.main, &bundleLanguageKey, path, .OBJC_ASSOCIATION_RETAIN)
    }
}

/// Source de vérité observable pour SwiftUI. Le `id(store.code)` sur la racine force la
/// reconstruction de l'arbre de vues quand la langue change (switch live).
@Observable
@MainActor
final class LanguageStore {
    private(set) var code: String

    init() {
        code = AppLocale.activeCode
        BundleLanguage.set(code)
        NotificationCenter.default.addObserver(
            forName: BundleLanguage.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let new = AppLocale.activeCode
                print("🌐LANG observer fired -> new code=\(new) (was \(self?.code ?? "nil"))")
                self?.code = new
            }
        }
    }
}
