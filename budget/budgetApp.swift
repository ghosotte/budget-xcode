//
//  budgetApp.swift
//  budget
//

import SwiftUI
import SwiftData
import BudgetKit

@main
struct budgetApp: App {

    var sharedContainer: ModelContainer = SharedStore.makeContainer()

    @State private var language = LanguageStore()

    init() {
        // Au lancement, scenePhase passe → .active et déclenche `onChange` dans ContentView
        // (quickSync → refreshMe). Le cold-start `.task` lance déjà syncAll (refreshMe aussi) :
        // sans garde, les deux couraient en parallèle → double GET /auth/me concurrent au démarrage.
        // On stampe `lastSyncAt` à l'instant du lancement pour que la garde 60s du scenePhase
        // supprime ce quickSync redondant. Les vrais retours de background (>60s) restent couverts.
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSyncAt")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(language)
                // Re-render live au changement de langue SANS changer l'identité de la vue
                // (sinon `.task` de cold-start re-tournerait → rafales de sync / rate limit).
                // Le `Bundle` swizzlé résout déjà les chaînes dans la langue du foyer actif.
                .environment(\.locale, Locale(identifier: language.code))
        }
        .modelContainer(sharedContainer)
    }
}
