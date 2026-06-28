import Foundation
import SwiftData

/// Backfill unique de `Expense.effectiveMonth` / `IncomeEntry.effectiveMonth` pour les lignes créées
/// avant que la propriété ne soit stockée (migration légère les a posées à `.distantPast`).
/// Délégué au `SyncEngine` (contexte background, fetch ciblé) → ne bloque pas le MainActor au cold start.
/// Idempotent + borné par un flag UserDefaults → s'exécute une seule fois après mise à jour.
@MainActor
enum EffectiveMonthBackfill {
    private static let doneKey = "migration.effectiveMonthBackfilled"

    static func runIfNeeded(container: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        do {
            try await SyncEngineProvider.shared(container).backfillEffectiveMonth()
            UserDefaults.standard.set(true, forKey: doneKey)
        } catch {
            SyncErrorReporter.report(error, context: "EffectiveMonthBackfill")
        }
    }
}
