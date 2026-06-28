//
//  QuickActions.swift
//  budget
//
//  Actions rapides hors app : appui long sur l'icône, Siri, Spotlight, Action Button.
//  Toutes ouvrent l'app sur le formulaire d'ajout pré-sélectionné (dépense / revenu).
//  Aucune écriture en arrière-plan : les intents ne font qu'ouvrir l'app.
//

import AppIntents
import SwiftUI

/// Pont intent → UI. L'intent (process app) écrit `pending` ; `ContentView` l'observe
/// et ouvre le formulaire. Le foyer ciblé est le foyer actif (`isDefault`), comme dans l'app.
@MainActor
@Observable
final class QuickActionRouter {
    static let shared = QuickActionRouter()
    var pending: TransactionFormKind?
    private init() {}
}

struct OpenAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter une dépense"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.shared.pending = .expense
        return .result()
    }
}

struct OpenAddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un revenu"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.shared.pending = .income
        return .result()
    }
}

/// Expose les intents à iOS : menu d'appui long sur l'icône (iOS 16+), Siri, Spotlight, Action Button.
struct BudgetAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAddExpenseIntent(),
            phrases: [
                "Ajouter une dépense dans \(.applicationName)",
                "Nouvelle dépense dans \(.applicationName)",
            ],
            shortTitle: "Ajouter une dépense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: OpenAddIncomeIntent(),
            phrases: [
                "Ajouter un revenu dans \(.applicationName)",
                "Nouveau revenu dans \(.applicationName)",
            ],
            shortTitle: "Ajouter un revenu",
            systemImageName: "plus.circle"
        )
    }
}
