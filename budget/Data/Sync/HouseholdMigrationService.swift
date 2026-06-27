import Foundation
import SwiftData

@MainActor
enum HouseholdMigrationService {

    private struct ImportRequest: Encodable {
        let name: String?
        let expenses: [ExpenseRow]
        let incomes: [IncomeRow]
        let budgetExpenseLines: [BudgetExpenseLineRow]
        let budgetIncomeLines: [BudgetIncomeLineRow]
        let recurring: [RecurringRow]

        enum CodingKeys: String, CodingKey {
            case name, expenses, incomes, recurring
            case budgetExpenseLines = "budget_expense_lines"
            case budgetIncomeLines = "budget_income_lines"
        }
    }

    private struct ExpenseRow: Encodable {
        let localId: String
        let amount: String
        let label: String
        let date: String
        let categoryId: Int?
        let subcategoryId: Int?
        let notes: String?
        let accountingMonth: String?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case amount, label, date, notes, tags
            case localId = "local_id"
            case categoryId = "category_id"
            case subcategoryId = "subcategory_id"
            case accountingMonth = "accounting_month"
        }
    }

    private struct IncomeRow: Encodable {
        let localId: String
        let amount: String
        let label: String
        let date: String
        let incomeCategoryId: Int?
        let notes: String?
        let accountingMonth: String?

        enum CodingKeys: String, CodingKey {
            case amount, label, date, notes
            case localId = "local_id"
            case incomeCategoryId = "income_category_id"
            case accountingMonth = "accounting_month"
        }
    }

    private struct BudgetExpenseLineRow: Encodable {
        let localId: String
        let categoryId: Int
        let subcategoryId: Int?
        let month: String
        let endMonth: String?
        let frequency: String
        let amount: String

        enum CodingKeys: String, CodingKey {
            case month, frequency, amount
            case localId = "local_id"
            case categoryId = "category_id"
            case subcategoryId = "subcategory_id"
            case endMonth = "end_month"
        }
    }

    private struct BudgetIncomeLineRow: Encodable {
        let localId: String
        let incomeCategoryId: Int
        let month: String
        let endMonth: String?
        let frequency: String
        let amount: String

        enum CodingKeys: String, CodingKey {
            case month, frequency, amount
            case localId = "local_id"
            case incomeCategoryId = "income_category_id"
            case endMonth = "end_month"
        }
    }

    private struct RecurringRow: Encodable {
        let localId: String
        let amount: String
        let label: String
        let dayOfMonth: Int
        let isActive: Bool
        let categoryId: Int?
        let subcategoryId: Int?

        enum CodingKeys: String, CodingKey {
            case amount, label
            case localId = "local_id"
            case dayOfMonth = "day_of_month"
            case isActive = "is_active"
            case categoryId = "category_id"
            case subcategoryId = "subcategory_id"
        }
    }

    private struct ImportResponse: Decodable {
        struct HouseholdRef: Decodable {
            let id: Int
            let name: String
        }
        struct MappingsBlock: Decodable {
            let expenses: [Mapping]
            let incomes: [Mapping]
            let budgetExpenseLines: [Mapping]
            let budgetIncomeLines: [Mapping]
            let recurring: [Mapping]

            enum CodingKeys: String, CodingKey {
                case expenses, incomes, recurring
                case budgetExpenseLines = "budget_expense_lines"
                case budgetIncomeLines = "budget_income_lines"
            }
        }

        struct Mapping: Decodable {
            let localId: String?
            let id: Int?

            enum CodingKeys: String, CodingKey {
                case id
                case localId = "local_id"
            }
        }

        let success: Bool
        let household: HouseholdRef?
        let mappings: MappingsBlock?
    }

    // MARK: — Entry point

    /// Migrate the local anonymous household into the user's current server household.
    /// Pushes a bulk snapshot, applies server IDs to local entities, then claims the
    /// anonymous household as server-bound.
    static func migrateAnonymousIfNeeded(session: AuthSession, context: ModelContext) async throws {
        guard session.justRegistered else { return }
        defer { session.justRegistered = false }

        guard let userId = session.user?.id,
              let serverHousehold = session.currentHousehold else { return }

        let households = try context.fetch(FetchDescriptor<Household>())

        if households.contains(where: {
            $0.serverId == serverHousehold.id && $0.ownerUserId == userId
        }) {
            return
        }

        let target = households.first(where: { $0.isAnonymous && $0.isDefault })
            ?? households.first(where: { $0.isAnonymous })
        guard let anonymous = target else { return }

        if hasMigratableData(anonymous) {
            try await pushSnapshot(anonymous: anonymous, context: context)
        }

        anonymous.serverId = serverHousehold.id
        anonymous.ownerUserId = userId
        anonymous.isAnonymous = false
        anonymous.name = serverHousehold.name
        for h in households { h.isDefault = (h == anonymous) }

        try context.save()
    }

    // MARK: — Snapshot push

    private static func hasMigratableData(_ household: Household) -> Bool {
        !household.expenses.isEmpty
            || !household.incomeEntries.isEmpty
            || !household.budgetExpenseLines.isEmpty
            || !household.budgetIncomes.isEmpty
            || !household.recurringExpenses.isEmpty
    }

    /// Promote a local anonymous household to a brand-new cloud household.
    /// Pushes the snapshot via /import-new, claims the foyer locally with returned IDs.
    static func promoteAnonymousToCloud(_ household: Household, name: String, session: AuthSession, context: ModelContext) async throws -> ServerHousehold {
        guard let userId = session.user?.id else { throw APIError.notAuthenticated }
        guard household.isAnonymous else { throw APIError.invalidResponse }

        let payload = buildPayload(household: household, name: name)
        let response: ImportResponse = try await APIClient.shared.send(
            ImportResponse.self,
            method: "POST",
            path: "/budget/household/import-new",
            body: payload
        )
        guard response.success,
              let mappings = response.mappings,
              let createdHousehold = response.household else {
            throw APIError.invalidResponse
        }

        applyMappings(mappings, household: household)

        let server = ServerHousehold(id: createdHousehold.id, name: createdHousehold.name)
        session.appendServerHousehold(server)

        household.serverId = server.id
        household.ownerUserId = userId
        household.isAnonymous = false
        household.name = server.name
        try context.save()

        return server
    }

    private static func buildPayload(household: Household, name: String?) -> ImportRequest {
        let expenseRows = household.expenses.map { e in
            ExpenseRow(
                localId: e.id.uuidString,
                amount: NSDecimalNumber(decimal: e.amount).stringValue,
                label: e.label,
                date: dayString(e.spentAt),
                categoryId: e.category?.serverId,
                subcategoryId: e.subcategory?.serverId,
                notes: e.notes,
                accountingMonth: e.accountingMonth.map(monthString),
                tags: e.tags.isEmpty ? nil : e.tags
            )
        }
        let incomeRows = household.incomeEntries.map { i in
            IncomeRow(
                localId: i.id.uuidString,
                amount: NSDecimalNumber(decimal: i.amount).stringValue,
                label: i.label,
                date: dayString(i.receivedAt),
                incomeCategoryId: i.incomeCategory?.serverId,
                notes: i.notes,
                accountingMonth: i.accountingMonth.map(monthString)
            )
        }
        let expenseLineRows: [BudgetExpenseLineRow] = household.budgetExpenseLines.compactMap { l in
            guard let categoryId = l.category?.serverId else { return nil }
            return BudgetExpenseLineRow(
                localId: l.id.uuidString,
                categoryId: categoryId,
                subcategoryId: l.subcategory?.serverId,
                month: monthString(l.month),
                endMonth: l.endMonth.map(monthString),
                frequency: l.frequency.rawValue,
                amount: NSDecimalNumber(decimal: l.amount).stringValue
            )
        }
        let incomeLineRows: [BudgetIncomeLineRow] = household.budgetIncomes.compactMap { l in
            guard let incomeCategoryId = l.incomeCategory?.serverId else { return nil }
            return BudgetIncomeLineRow(
                localId: l.id.uuidString,
                incomeCategoryId: incomeCategoryId,
                month: monthString(l.month),
                endMonth: l.endMonth.map(monthString),
                frequency: l.frequency.rawValue,
                amount: NSDecimalNumber(decimal: l.amount).stringValue
            )
        }
        let recurringRows = household.recurringExpenses.map { r in
            RecurringRow(
                localId: r.id.uuidString,
                amount: NSDecimalNumber(decimal: r.amount).stringValue,
                label: r.label,
                dayOfMonth: r.dayOfMonth,
                isActive: r.isActive,
                categoryId: r.category?.serverId,
                subcategoryId: r.subcategory?.serverId
            )
        }
        return ImportRequest(
            name: name,
            expenses: expenseRows,
            incomes: incomeRows,
            budgetExpenseLines: expenseLineRows,
            budgetIncomeLines: incomeLineRows,
            recurring: recurringRows
        )
    }

    private static func pushSnapshot(anonymous: Household, context: ModelContext) async throws {
        let payload = buildPayload(household: anonymous, name: nil)
        let response: ImportResponse = try await APIClient.shared.send(
            ImportResponse.self,
            method: "POST",
            path: "/budget/household/import",
            body: payload
        )
        guard response.success, let mappings = response.mappings else {
            throw APIError.invalidResponse
        }
        applyMappings(mappings, household: anonymous)
    }

    private static func applyMappings(_ mappings: ImportResponse.MappingsBlock, household: Household) {
        let expensesById = Dictionary(uniqueKeysWithValues: household.expenses.map { ($0.id.uuidString, $0) })
        for m in mappings.expenses {
            guard let local = m.localId, let serverId = m.id, let entity = expensesById[local] else { continue }
            entity.serverId = serverId
            entity.syncStatus = .synced
        }

        let incomesById = Dictionary(uniqueKeysWithValues: household.incomeEntries.map { ($0.id.uuidString, $0) })
        for m in mappings.incomes {
            guard let local = m.localId, let serverId = m.id, let entity = incomesById[local] else { continue }
            entity.serverId = serverId
            entity.syncStatus = .synced
        }

        let expenseLinesById = Dictionary(uniqueKeysWithValues: household.budgetExpenseLines.map { ($0.id.uuidString, $0) })
        for m in mappings.budgetExpenseLines {
            guard let local = m.localId, let serverId = m.id, let entity = expenseLinesById[local] else { continue }
            entity.serverId = serverId
            entity.syncStatus = .synced
        }

        let incomeLinesById = Dictionary(uniqueKeysWithValues: household.budgetIncomes.map { ($0.id.uuidString, $0) })
        for m in mappings.budgetIncomeLines {
            guard let local = m.localId, let serverId = m.id, let entity = incomeLinesById[local] else { continue }
            entity.serverId = serverId
            entity.syncStatus = .synced
        }

        let recurringById = Dictionary(uniqueKeysWithValues: household.recurringExpenses.map { ($0.id.uuidString, $0) })
        for m in mappings.recurring {
            guard let local = m.localId, let serverId = m.id, let entity = recurringById[local] else { continue }
            entity.serverId = serverId
            entity.syncStatus = .synced
        }
    }

    // MARK: — Helpers

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func monthString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }
}
