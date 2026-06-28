import Foundation
import SwiftData
import BudgetKit

@MainActor
enum MonthSyncService {

    private static var lastFetch: [String: Date] = [:]
    private static var lastBudgetFetch: [String: Date] = [:]
    private static var inflight: Set<String> = []
    /// Transactions changent souvent → throttle court. `/transactions` est rapide (~80ms).
    private static let throttle: TimeInterval = 300
    /// Lignes budget = config mensuelle quasi figée + endpoint `/budget` lent (~2.5s) → throttle long
    /// pour ne pas repayer ce coût à chaque aller-retour entre mois.
    private static let budgetThrottle: TimeInterval = 1800

    private static func key(householdServerId: Int, month: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(householdServerId):\(components.year ?? 0)-\(components.month ?? 0)"
    }

    /// Refresh transactions + budget lines for the given month into the active claimed household.
    /// No-op if user is not authenticated, foyer actif is anonymous, or call was throttled.
    /// Transactions et budget ont des throttles distincts → revisiter un mois ne relance pas le `/budget` lent.
    /// Silent on network errors — cache local stays as fallback.
    static func refreshMonth(
        _ rawMonth: Date,
        session: AuthSession,
        context: ModelContext,
        force: Bool = false
    ) async {
        guard session.isAuthenticated, let userId = session.user?.id else { return }

        let month = Calendar.current.startOfMonth(for: rawMonth)
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        guard let household = households.first(where: \.isDefault),
              !household.isAnonymous,
              !household.isOrphan,
              let serverId = household.serverId,
              household.ownerUserId == userId else { return }

        guard serverId == session.currentHousehold?.id else {
            // Active foyer ne matche pas le token courant — switch en cours probable.
            return
        }

        let key = key(householdServerId: serverId, month: month)
        if inflight.contains(key) { return }

        let needTransactions = force || lastFetch[key].map { Date().timeIntervalSince($0) >= throttle } ?? true
        let needBudget = force || lastBudgetFetch[key].map { Date().timeIntervalSince($0) >= budgetThrottle } ?? true
        guard needTransactions || needBudget else { return }

        inflight.insert(key)
        defer { inflight.remove(key) }

        // Push (contexte principal) ET pull (contexte background) dans LE MÊME verrou sérialisé :
        // le pull s'exécute après que le push a committé → le fetch background voit les lignes déjà
        // poussées (matchées par serverId) → pas de doublon / suppression concurrente inter-contextes.
        // Le travail lourd reste sur l'engine background (l'await libère le MainActor → scroll fluide).
        try? await SyncLock.run {
            do {
                try await PushService.pushPending(session: session, context: context)
                try await SyncEngineProvider.shared(context.container).pullMonth(
                    householdServerId: serverId, userId: userId, month: month,
                    needTransactions: needTransactions, needBudget: needBudget
                )
                if needTransactions { lastFetch[key] = Date() }
                if needBudget { lastBudgetFetch[key] = Date() }
            } catch {
                SyncErrorReporter.report(error, context: "MonthSyncService.refreshMonth(\(key))")
            }
        }
    }

    static func invalidate() {
        lastFetch.removeAll()
        lastBudgetFetch.removeAll()
    }

    // MARK: — Recurring templates (not month-scoped)

    private static var recurringLastFetch: [Int: Date] = [:]
    private static var recurringInflight: Set<Int> = []

    static func refreshRecurring(session: AuthSession, context: ModelContext, force: Bool = false) async {
        guard session.isAuthenticated, let userId = session.user?.id else { return }
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        guard let household = households.first(where: \.isDefault),
              !household.isAnonymous,
              !household.isOrphan,
              let serverId = household.serverId,
              household.ownerUserId == userId,
              serverId == session.currentHousehold?.id else { return }

        if recurringInflight.contains(serverId) { return }
        if !force, let last = recurringLastFetch[serverId], Date().timeIntervalSince(last) < throttle { return }
        recurringInflight.insert(serverId)
        defer { recurringInflight.remove(serverId) }

        try? await SyncLock.run {
            do {
                try await PushService.pushPending(session: session, context: context)
                try await SyncEngineProvider.shared(context.container).pullRecurring(
                    householdServerId: serverId, userId: userId
                )
                recurringLastFetch[serverId] = Date()
            } catch {
                SyncErrorReporter.report(error, context: "MonthSyncService.refreshRecurring")
            }
        }
    }
}
