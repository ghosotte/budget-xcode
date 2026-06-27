import Foundation
import SwiftData

/// iOS never generates recurring expenses — the backend is authoritative.
/// Templates are stored locally but don't materialize into transactions.
/// This one-shot purge removes leftovers from previous client-side generation
/// that bypassed sync (no serverId, never pushed).
enum RecurringCleanupService {
    static func purgeOrphanedLocalInstances(context: ModelContext) {
        let orphans = (try? context.fetch(FetchDescriptor<Expense>()))?
            .filter { $0.recurringTemplate != nil && $0.serverId == nil } ?? []
        guard !orphans.isEmpty else { return }
        for expense in orphans {
            context.delete(expense)
        }
        try? context.save()
    }
}
