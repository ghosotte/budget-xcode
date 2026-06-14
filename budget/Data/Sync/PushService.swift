import Foundation
import SwiftData

// MARK: — Tombstones de suppression

enum PendingDeleteStore {
    struct Tombstone: Codable, Equatable {
        enum Kind: String, Codable {
            case expense, income, recurring, budgetExpenseLine, budgetIncomeLine
        }

        let kind: Kind
        let serverId: Int
        let monthString: String?
    }

    private static let key = "sync.pendingDeletes"

    static var all: [Tombstone] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Tombstone].self, from: data)) ?? []
    }

    static func add(_ kind: Tombstone.Kind, serverId: Int, month: String? = nil) {
        var tombstones = all
        let tombstone = Tombstone(kind: kind, serverId: serverId, monthString: month)
        guard !tombstones.contains(tombstone) else { return }
        tombstones.append(tombstone)
        save(tombstones)
    }

    static func remove(_ tombstone: Tombstone) {
        save(all.filter { $0 != tombstone })
    }

    private static func save(_ tombstones: [Tombstone]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(tombstones), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: — File d'attente foyers (rename / delete) offline

enum PendingHouseholdOpStore {
    enum Op: Codable, Equatable {
        case rename(serverId: Int, name: String)
        case delete(serverId: Int)

        var serverId: Int {
            switch self {
            case .rename(let id, _), .delete(let id): return id
            }
        }
    }

    private static let key = "sync.pendingHouseholdOps"

    static var all: [Op] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Op].self, from: data)) ?? []
    }

    static func enqueueRename(serverId: Int, name: String) {
        var ops = all.filter {
            if case .rename(let id, _) = $0 { return id != serverId }
            return true
        }
        ops.append(.rename(serverId: serverId, name: name))
        save(ops)
    }

    static func enqueueDelete(serverId: Int) {
        // Drop any pending rename for this foyer — delete supersedes.
        var ops = all.filter { $0.serverId != serverId }
        ops.append(.delete(serverId: serverId))
        save(ops)
    }

    static func remove(_ op: Op) {
        save(all.filter { $0 != op })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ ops: [Op]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(ops), forKey: key)
    }
}

// MARK: — Push

@MainActor
enum PushService {

    private struct SimpleResponse: Decodable {
        let success: Bool
    }

    // MARK: Hooks appelés par les vues

    static func markForUpload(_ syncStatus: inout SyncStatus, household: Household?) {
        if household?.serverId != nil {
            syncStatus = .pendingUpload
        }
    }

    static func afterLocalChange(session: AuthSession, context: ModelContext) {
        guard session.isAuthenticated else { return }
        Task {
            do {
                try await pushPending(session: session, context: context)
            } catch {
                SyncErrorReporter.report(error, context: "PushService.afterLocalChange")
            }
        }
    }

    static func deleteExpense(_ expense: Expense, session: AuthSession, context: ModelContext) {
        if let serverId = expense.serverId, expense.household?.serverId != nil {
            PendingDeleteStore.add(.expense, serverId: serverId)
        }
        context.delete(expense)
        context.safeSave("PushService.deleteExpense")
        afterLocalChange(session: session, context: context)
    }

    static func deleteIncome(_ income: IncomeEntry, session: AuthSession, context: ModelContext) {
        if let serverId = income.serverId, income.household?.serverId != nil {
            PendingDeleteStore.add(.income, serverId: serverId)
        }
        context.delete(income)
        context.safeSave("PushService.deleteIncome")
        afterLocalChange(session: session, context: context)
    }

    static func deleteRecurring(_ template: RecurringExpense, session: AuthSession, context: ModelContext) {
        if let serverId = template.serverId, template.household?.serverId != nil {
            PendingDeleteStore.add(.recurring, serverId: serverId)
        }
        context.delete(template)
        context.safeSave("PushService.deleteRecurring")
        afterLocalChange(session: session, context: context)
    }

    static func deleteBudgetExpenseLine(_ line: BudgetExpenseLine, viewMonth: Date, session: AuthSession, context: ModelContext) {
        if let serverId = line.serverId, line.household?.serverId != nil {
            PendingDeleteStore.add(.budgetExpenseLine, serverId: serverId, month: monthString(viewMonth))
        }
        context.delete(line)
        context.safeSave("PushService.deleteBudgetExpenseLine")
        afterLocalChange(session: session, context: context)
    }

    static func deleteBudgetIncomeLine(_ line: BudgetIncome, viewMonth: Date, session: AuthSession, context: ModelContext) {
        if let serverId = line.serverId, line.household?.serverId != nil {
            PendingDeleteStore.add(.budgetIncomeLine, serverId: serverId, month: monthString(viewMonth))
        }
        context.delete(line)
        context.safeSave("PushService.deleteBudgetIncomeLine")
        afterLocalChange(session: session, context: context)
    }

    // MARK: Push des changements en attente

    static func pushPending(session: AuthSession, context: ModelContext) async throws {
        guard session.isAuthenticated, let userId = session.user?.id else { return }

        try await pushTombstones()
        await pushHouseholdOps(session: session)

        let households = try context.fetch(FetchDescriptor<Household>())
        guard let household = households.first(where: {
            $0.serverId == session.currentHousehold?.id && $0.ownerUserId == userId
        }) else { return }

        try await pushExpenses(household: household)
        try await pushIncomes(household: household)
        try await pushRecurring(household: household)
        try await pushBudgetExpenseLines(household: household)
        try await pushBudgetIncomeLines(household: household)
        try context.save()
    }

    private static func pushHouseholdOps(session: AuthSession) async {
        for op in PendingHouseholdOpStore.all {
            do {
                switch op {
                case .rename(let serverId, let name):
                    try await session.renameCloudHousehold(serverId: serverId, name: name)
                case .delete(let serverId):
                    try await session.deleteCloudHousehold(serverId: serverId)
                }
                PendingHouseholdOpStore.remove(op)
            } catch {
                if case let APIError.http(status, _) = error {
                    if (400..<500).contains(status) {
                        // Non-recoverable client error → drop op.
                        PendingHouseholdOpStore.remove(op)
                        continue
                    }
                    // 5xx: keep + stop replay this round.
                    return
                }
                // URLError or anything else → keep + stop replay.
                return
            }
        }
    }

    private static func pushTombstones() async throws {
        for tombstone in PendingDeleteStore.all {
            do {
                switch tombstone.kind {
                case .expense:
                    _ = try await APIClient.shared.send(
                        SimpleResponse.self, method: "DELETE",
                        path: "/budget/transactions/\(tombstone.serverId)",
                        body: ["type": "expense"]
                    )
                case .income:
                    _ = try await APIClient.shared.send(
                        SimpleResponse.self, method: "DELETE",
                        path: "/budget/transactions/\(tombstone.serverId)",
                        body: ["type": "income"]
                    )
                case .recurring:
                    _ = try await APIClient.shared.send(
                        SimpleResponse.self, method: "DELETE",
                        path: "/budget/recurring/\(tombstone.serverId)"
                    )
                case .budgetExpenseLine:
                    let m = tombstone.monthString ?? monthString(.now)
                    _ = try await APIClient.shared.send(
                        SimpleResponse.self, method: "DELETE",
                        path: "/budget/budget/expense-lines/\(tombstone.serverId)",
                        query: ["month": m]
                    )
                case .budgetIncomeLine:
                    let m = tombstone.monthString ?? monthString(.now)
                    _ = try await APIClient.shared.send(
                        SimpleResponse.self, method: "DELETE",
                        path: "/budget/budget/income-lines/\(tombstone.serverId)",
                        query: ["month": m]
                    )
                }
                PendingDeleteStore.remove(tombstone)
            } catch let APIError.http(status, _) where status == 404 {
                PendingDeleteStore.remove(tombstone)
            }
        }
    }

    private struct TransactionPushResponse: Decodable {
        struct Transaction: Decodable {
            let id: Int
        }

        let success: Bool
        let transaction: Transaction?
    }

    private static func pushExpenses(household: Household) async throws {
        for expense in household.expenses where expense.syncStatus == .pendingUpload {
            var body: [String: String?] = [
                "type": "expense",
                "amount": NSDecimalNumber(decimal: expense.amount).stringValue,
                "label": expense.label,
                "date": dayString(expense.spentAt),
                "status": expense.status.rawValue,
                "category_id": expense.category?.serverId.map(String.init),
                "subcategory_id": expense.subcategory?.serverId.map(String.init),
                "notes": expense.notes,
                "accounting_month": expense.accountingMonth.map(monthString),
            ]
            body = body.filter { $0.value != nil }

            if let serverId = expense.serverId {
                _ = try await APIClient.shared.send(
                    TransactionPushResponse.self, method: "PATCH",
                    path: "/budget/transactions/\(serverId)", body: body
                )
            } else {
                let response = try await APIClient.shared.send(
                    TransactionPushResponse.self, method: "POST",
                    path: "/budget/transactions", body: body
                )
                expense.serverId = response.transaction?.id
            }
            expense.syncStatus = .synced
        }
    }

    private static func pushIncomes(household: Household) async throws {
        for income in household.incomeEntries where income.syncStatus == .pendingUpload {
            var body: [String: String?] = [
                "type": "income",
                "amount": NSDecimalNumber(decimal: income.amount).stringValue,
                "label": income.label,
                "date": dayString(income.receivedAt),
                "status": income.status.rawValue,
                "income_category_id": income.incomeCategory?.serverId.map(String.init),
                "notes": income.notes,
                "accounting_month": income.accountingMonth.map(monthString),
            ]
            body = body.filter { $0.value != nil }

            if let serverId = income.serverId {
                _ = try await APIClient.shared.send(
                    TransactionPushResponse.self, method: "PATCH",
                    path: "/budget/transactions/\(serverId)", body: body
                )
            } else {
                let response = try await APIClient.shared.send(
                    TransactionPushResponse.self, method: "POST",
                    path: "/budget/transactions", body: body
                )
                income.serverId = response.transaction?.id
            }
            income.syncStatus = .synced
        }
    }

    private struct RecurringPushResponse: Decodable {
        struct Recurring: Decodable {
            let id: Int
            let isActive: Bool

            enum CodingKeys: String, CodingKey {
                case id
                case isActive = "is_active"
            }
        }

        let success: Bool
        let recurring: Recurring?
    }

    private static func pushRecurring(household: Household) async throws {
        for template in household.recurringExpenses where template.syncStatus == .pendingUpload {
            var body: [String: String?] = [
                "amount": NSDecimalNumber(decimal: template.amount).stringValue,
                "label": template.label,
                "day_of_month": String(template.dayOfMonth),
                "auto_confirm": template.autoConfirm ? "1" : "0",
                "category_id": template.category?.serverId.map(String.init),
                "subcategory_id": template.subcategory?.serverId.map(String.init),
            ]
            body = body.filter { $0.value != nil }

            let response: RecurringPushResponse
            if let serverId = template.serverId {
                response = try await APIClient.shared.send(
                    RecurringPushResponse.self, method: "PATCH",
                    path: "/budget/recurring/\(serverId)", body: body
                )
            } else {
                response = try await APIClient.shared.send(
                    RecurringPushResponse.self, method: "POST",
                    path: "/budget/recurring", body: body
                )
                template.serverId = response.recurring?.id
            }

            if let serverId = template.serverId,
               let serverActive = response.recurring?.isActive,
               serverActive != template.isActive {
                _ = try await APIClient.shared.send(
                    RecurringPushResponse.self, method: "PATCH",
                    path: "/budget/recurring/\(serverId)/toggle"
                )
            }
            template.syncStatus = .synced
        }
    }

    // MARK: Lignes budgétaires — push pendingUpload

    private struct BudgetExpenseLinePushResponse: Decodable {
        struct Inner: Decodable { let id: Int }
        let success: Bool
        let expenseLine: Inner?

        enum CodingKeys: String, CodingKey {
            case success
            case expenseLine = "expense_line"
        }
    }

    private struct BudgetIncomeLinePushResponse: Decodable {
        struct Inner: Decodable { let id: Int }
        let success: Bool
        let incomeLine: Inner?

        enum CodingKeys: String, CodingKey {
            case success
            case incomeLine = "income_line"
        }
    }

    private static func pushBudgetExpenseLines(household: Household) async throws {
        for line in household.budgetExpenseLines where line.syncStatus == .pendingUpload {
            guard let categoryId = line.category?.serverId else { continue }
            var body: [String: String?] = [
                "category_id": String(categoryId),
                "subcategory_id": line.subcategory?.serverId.map(String.init),
                "month": monthString(line.month),
                "frequency": line.frequency.rawValue,
                "amount": NSDecimalNumber(decimal: line.amount).stringValue,
            ]
            body = body.filter { $0.value != nil }

            if let serverId = line.serverId {
                var patchBody = body
                patchBody["edit_scope"] = "from_this_month"
                _ = try await APIClient.shared.send(
                    BudgetExpenseLinePushResponse.self, method: "PATCH",
                    path: "/budget/budget/expense-lines/\(serverId)", body: patchBody
                )
            } else {
                let response = try await APIClient.shared.send(
                    BudgetExpenseLinePushResponse.self, method: "POST",
                    path: "/budget/budget/expense-lines", body: body
                )
                line.serverId = response.expenseLine?.id
            }
            line.syncStatus = .synced
        }
    }

    private static func pushBudgetIncomeLines(household: Household) async throws {
        for line in household.budgetIncomes where line.syncStatus == .pendingUpload {
            guard let incomeCategoryId = line.incomeCategory?.serverId else { continue }
            var body: [String: String?] = [
                "income_category_id": String(incomeCategoryId),
                "month": monthString(line.month),
                "frequency": line.frequency.rawValue,
                "amount": NSDecimalNumber(decimal: line.amount).stringValue,
            ]
            body = body.filter { $0.value != nil }

            if let serverId = line.serverId {
                var patchBody = body
                patchBody["edit_scope"] = "from_this_month"
                _ = try await APIClient.shared.send(
                    BudgetIncomeLinePushResponse.self, method: "PATCH",
                    path: "/budget/budget/income-lines/\(serverId)", body: patchBody
                )
            } else {
                let response = try await APIClient.shared.send(
                    BudgetIncomeLinePushResponse.self, method: "POST",
                    path: "/budget/budget/income-lines", body: body
                )
                line.serverId = response.incomeLine?.id
            }
            line.syncStatus = .synced
        }
    }

    // MARK: Lignes budgétaires — remote-first (deprecated, kept for backwards compat)

    static func isRemoteBudget(_ household: Household?, session: AuthSession) -> Bool {
        session.isAuthenticated
            && household?.serverId != nil
            && household?.serverId == session.currentHousehold?.id
            && household?.ownerUserId != nil
            && household?.ownerUserId == session.user?.id
            && household?.isOrphan == false
    }

    static func createExpenseLineRemote(
        category: Category, subcategory: Subcategory?, month: Date,
        frequency: Frequency, amount: Decimal
    ) async throws {
        guard let categoryId = category.serverId else { throw APIError.invalidResponse }
        var body: [String: String?] = [
            "category_id": String(categoryId),
            "subcategory_id": subcategory?.serverId.map(String.init),
            "month": monthString(month),
            "frequency": frequency.rawValue,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
        ]
        body = body.filter { $0.value != nil }
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "POST", path: "/budget/budget/expense-lines", body: body
        )
    }

    static func updateExpenseLineRemote(
        serverId: Int, month: Date, scope: EditScope, frequency: Frequency, amount: Decimal
    ) async throws {
        let body: [String: String] = [
            "month": monthString(month),
            "frequency": frequency.rawValue,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "edit_scope": scope == .thisMonthOnly ? "this_month_only" : "from_this_month",
        ]
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "PATCH", path: "/budget/budget/expense-lines/\(serverId)", body: body
        )
    }

    static func deleteExpenseLineRemote(serverId: Int, month: Date) async throws {
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "DELETE",
            path: "/budget/budget/expense-lines/\(serverId)",
            query: ["month": monthString(month)]
        )
    }

    static func createIncomeLineRemote(
        incomeCategory: IncomeCategory, month: Date, frequency: Frequency, amount: Decimal
    ) async throws {
        guard let categoryId = incomeCategory.serverId else { throw APIError.invalidResponse }
        let body: [String: String] = [
            "income_category_id": String(categoryId),
            "month": monthString(month),
            "frequency": frequency.rawValue,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
        ]
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "POST", path: "/budget/budget/income-lines", body: body
        )
    }

    static func updateIncomeLineRemote(
        serverId: Int, month: Date, scope: EditScope, frequency: Frequency, amount: Decimal
    ) async throws {
        let body: [String: String] = [
            "month": monthString(month),
            "frequency": frequency.rawValue,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "edit_scope": scope == .thisMonthOnly ? "this_month_only" : "from_this_month",
        ]
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "PATCH", path: "/budget/budget/income-lines/\(serverId)", body: body
        )
    }

    static func deleteIncomeLineRemote(serverId: Int, month: Date) async throws {
        _ = try await APIClient.shared.send(
            SimpleResponse.self, method: "DELETE",
            path: "/budget/budget/income-lines/\(serverId)",
            query: ["month": monthString(month)]
        )
    }

    // MARK: Helpers

    private static func dayString(_ date: Date) -> String {
        MonthMath.dayString(date)
    }

    private static func monthString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }
}
