import Foundation
import SwiftData

/// Backfill unique de `Expense.effectiveMonth` / `IncomeEntry.effectiveMonth` pour les lignes créées
/// avant que la propriété ne soit stockée (migration légère les a posées à `.distantPast`).
/// Idempotent et borné par un flag UserDefaults → s'exécute une seule fois après mise à jour.
@MainActor
enum EffectiveMonthBackfill {
    private static let doneKey = "migration.effectiveMonthBackfilled"

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        // Ne traite que les lignes au sentinel `.distantPast` : les rangées déjà correctes
        // (créées via init après mise à jour) sont ignorées.
        let sentinel = Date.distantPast

        if let expenses = try? context.fetch(FetchDescriptor<Expense>()) {
            for expense in expenses where expense.effectiveMonth == sentinel {
                expense.refreshEffectiveMonth()
            }
        }
        if let incomes = try? context.fetch(FetchDescriptor<IncomeEntry>()) {
            for income in incomes where income.effectiveMonth == sentinel {
                income.refreshEffectiveMonth()
            }
        }

        context.safeSave("EffectiveMonthBackfill")
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
