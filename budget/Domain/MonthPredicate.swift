import Foundation
import SwiftData

/// Prédicats `@Query` scopant les transactions à un seul mois côté SQLite (via `effectiveMonth` stocké).
/// Évite de charger tout l'historique en RAM. Fenêtre `[début, début+1 mois[` — range plutôt qu'égalité
/// de `Date` exacte pour rester robuste aux décalages de fuseau.
extension Expense {
    static func monthPredicate(_ month: Date) -> Predicate<Expense> {
        let start = Calendar.current.startOfMonth(for: month)
        let next = Calendar.current.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return #Predicate<Expense> { $0.effectiveMonth >= start && $0.effectiveMonth < next }
    }
}

extension IncomeEntry {
    static func monthPredicate(_ month: Date) -> Predicate<IncomeEntry> {
        let start = Calendar.current.startOfMonth(for: month)
        let next = Calendar.current.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return #Predicate<IncomeEntry> { $0.effectiveMonth >= start && $0.effectiveMonth < next }
    }
}

// Lignes budget « actives pour le mois » = `month <= m && (endMonth == nil || endMonth >= m)`
// (cf. `isActive(for:)`). Scoper le `@Query` évite de charger/recalculer TOUTES les lignes (tous mois)
// à chaque merge background → main, ce qui figeait Dashboard + onglet Budget.
extension BudgetExpenseLine {
    static func activeMonthPredicate(_ month: Date) -> Predicate<BudgetExpenseLine> {
        let m = Calendar.current.startOfMonth(for: month)
        let far = Date.distantFuture
        return #Predicate<BudgetExpenseLine> { $0.month <= m && ($0.endMonth ?? far) >= m }
    }
}

extension BudgetIncome {
    static func activeMonthPredicate(_ month: Date) -> Predicate<BudgetIncome> {
        let m = Calendar.current.startOfMonth(for: month)
        let far = Date.distantFuture
        return #Predicate<BudgetIncome> { $0.month <= m && ($0.endMonth ?? far) >= m }
    }
}
