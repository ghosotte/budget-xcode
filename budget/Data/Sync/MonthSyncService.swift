import Foundation
import SwiftData

@MainActor
enum MonthSyncService {

    private static var lastFetch: [String: Date] = [:]
    private static var inflight: Set<String> = []
    private static let throttle: TimeInterval = 30

    private static func key(householdServerId: Int, month: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(householdServerId):\(components.year ?? 0)-\(components.month ?? 0)"
    }

    /// Refresh transactions + budget lines for the given month into the active claimed household.
    /// No-op if user is not authenticated, foyer actif is anonymous, or call was throttled.
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
        if !force, let last = lastFetch[key], Date().timeIntervalSince(last) < throttle { return }
        inflight.insert(key)
        defer { inflight.remove(key) }

        do {
            try await PushService.pushPending(session: session, context: context)
            try await SyncService.pullTransactions(household: household, month: month, context: context)
            try await SyncService.pullBudgetLines(household: household, month: month, context: context)
            try context.save()
            lastFetch[key] = Date()
        } catch {
            // Silent — local cache remains source of truth for UI.
        }
    }

    static func invalidate() {
        lastFetch.removeAll()
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

        do {
            try await PushService.pushPending(session: session, context: context)
            try await SyncService.pullRecurring(household: household, context: context)
            try context.save()
            recurringLastFetch[serverId] = Date()
        } catch {
            // Silent
        }
    }
}
