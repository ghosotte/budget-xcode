//
//  budgetApp.swift
//  budget
//

import SwiftUI
import SwiftData

@main
struct budgetApp: App {

    var sharedContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BudgetMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    @State private var language = LanguageStore()

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
