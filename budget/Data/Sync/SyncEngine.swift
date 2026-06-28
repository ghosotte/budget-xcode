import Foundation
import SwiftData
import BudgetKit

/// Exécute les pulls lourds (transactions, budget, catégories, récurrents) sur un contexte SwiftData
/// **background** au lieu du MainActor. Avant, ces upserts (20-35KB → centaines de lignes) tournaient
/// sur le main thread → il était bloqué pendant le décodage+insertion, donc l'UI ne scrollait pas et
/// les continuations réseau (qui reprenaient sur le MainActor) attendaient ~3s.
///
/// Les `save()` du contexte background se mergent automatiquement dans le contexte principal → les
/// `@Query` des vues se rafraîchissent. Les objets modèles ne traversent pas les contextes : on
/// retrouve le foyer par `serverId` dans le contexte de l'acteur.
@ModelActor
actor SyncEngine {

    private func household(serverId: Int, userId: Int) throws -> Household? {
        let households = try modelContext.fetch(FetchDescriptor<Household>())
        return households.first { $0.serverId == serverId && $0.ownerUserId == userId }
    }

    func pullMonth(
        householdServerId: Int, userId: Int, month: Date,
        needTransactions: Bool, needBudget: Bool
    ) async throws {
        guard let household = try household(serverId: householdServerId, userId: userId) else { return }
        if needTransactions {
            try await SyncService.pullTransactions(household: household, month: month, context: modelContext)
        }
        if needBudget {
            try await SyncService.pullBudgetLines(household: household, month: month, context: modelContext)
        }
        if modelContext.hasChanges { try modelContext.save() }
    }

    func pullBudgetLines(householdServerId: Int, userId: Int, month: Date) async throws {
        guard let household = try household(serverId: householdServerId, userId: userId) else { return }
        try await SyncService.pullBudgetLines(household: household, month: month, context: modelContext)
        if modelContext.hasChanges { try modelContext.save() }
    }

    func pullRecurring(householdServerId: Int, userId: Int) async throws {
        guard let household = try household(serverId: householdServerId, userId: userId) else { return }
        try await SyncService.pullRecurring(household: household, context: modelContext)
        if modelContext.hasChanges { try modelContext.save() }
    }

    func pullCategories() async throws {
        try await SyncService.pullCategories(context: modelContext)
        if modelContext.hasChanges { try modelContext.save() }
    }

    /// Backfill unique de `effectiveMonth` (lignes au sentinel `.distantPast`) sur le contexte
    /// background : fetch CIBLÉ par prédicat (pas toute la table) + hors MainActor → pas de hang au
    /// premier lancement post-mise à jour. Prédicat sur `Date` (pas un enum) → fiable.
    func backfillEffectiveMonth() async throws {
        let sentinel = Date.distantPast
        let expenses = (try? modelContext.fetch(
            FetchDescriptor<Expense>(predicate: #Predicate { $0.effectiveMonth == sentinel })
        )) ?? []
        for expense in expenses { expense.refreshEffectiveMonth() }
        let incomes = (try? modelContext.fetch(
            FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.effectiveMonth == sentinel })
        )) ?? []
        for income in incomes { income.refreshEffectiveMonth() }
        if modelContext.hasChanges { try modelContext.save() }
    }
}

/// Accès partagé à un `SyncEngine` unique (un seul contexte background réutilisé).
@MainActor
enum SyncEngineProvider {
    private static var engine: SyncEngine?

    static func shared(_ container: ModelContainer) -> SyncEngine {
        if let engine { return engine }
        let created = SyncEngine(modelContainer: container)
        engine = created
        return created
    }

    /// Jette le contexte background mis en cache. À appeler quand le contexte principal supprime des
    /// données (logout, changement de foyer) : sinon l'engine sert des objets périmés / ré-insère du supprimé.
    static func reset() {
        engine = nil
    }
}
