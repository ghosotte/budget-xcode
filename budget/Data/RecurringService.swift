import Foundation
import SwiftData
import BudgetKit

/// iOS never generates recurring expenses — the backend is authoritative.
/// Templates are stored locally but don't materialize into transactions.
/// This one-shot purge removes leftovers from previous client-side generation
/// that bypassed sync (no serverId, never pushed).
enum RecurringCleanupService {
    static func purgeOrphanedLocalInstances(context: ModelContext) {
        // Fetch ciblé (orphelins seulement, en général zéro) plutôt que charger TOUT l'historique
        // des dépenses en mémoire sur le MainActor à chaque cold start.
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.recurringTemplate != nil && $0.serverId == nil }
        )
        let orphans = (try? context.fetch(descriptor)) ?? []
        guard !orphans.isEmpty else { return }
        for expense in orphans {
            context.delete(expense)
        }
        try? context.save()
    }
}
