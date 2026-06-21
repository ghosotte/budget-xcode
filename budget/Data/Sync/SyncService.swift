import Foundation
import SwiftData

@MainActor
enum SyncService {

    struct CategoryDTO: Decodable {
        let id: Int
        let name: String
        let nameEn: String?
        let emoji: String
        let sortOrder: Int
        let subcategories: [SubcategoryDTO]?

        enum CodingKeys: String, CodingKey {
            case id, name, emoji, subcategories
            case nameEn = "name_en"
            case sortOrder = "sort_order"
        }
    }

    struct SubcategoryDTO: Decodable {
        let id: Int
        let name: String
        let nameEn: String?
        let emoji: String
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case id, name, emoji
            case nameEn = "name_en"
            case sortOrder = "sort_order"
        }
    }

    struct TransactionDTO: Decodable {
        struct Ref: Decodable {
            let id: Int
            let name: String
            let emoji: String
        }

        let id: Int
        let type: String
        let amount: String
        let label: String
        let date: String
        let accountingMonth: String?
        let status: String
        let category: Ref?
        let subcategory: Ref?
        let incomeCategory: Ref?
        let tags: [String]
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case id, type, amount, label, date, status, category, subcategory, tags, notes
            case accountingMonth = "accounting_month"
            case incomeCategory = "income_category"
        }
    }

    struct BudgetLineDTO: Decodable {
        struct Ref: Decodable {
            let id: Int
            let name: String
            let emoji: String
        }

        let id: Int
        let category: Ref?
        let subcategory: Ref?
        let incomeCategory: Ref?
        let month: String
        let endMonth: String?
        let frequency: String
        let amount: String

        enum CodingKeys: String, CodingKey {
            case id, category, subcategory, month, frequency, amount
            case incomeCategory = "income_category"
            case endMonth = "end_month"
        }
    }

    struct RecurringDTO: Decodable {
        struct Ref: Decodable {
            let id: Int
            let name: String
            let emoji: String
        }

        let id: Int
        let amount: String
        let label: String
        let dayOfMonth: Int
        let isActive: Bool
        let autoConfirm: Bool
        let category: Ref?
        let subcategory: Ref?

        enum CodingKeys: String, CodingKey {
            case id, amount, label, category, subcategory
            case dayOfMonth = "day_of_month"
            case isActive = "is_active"
            case autoConfirm = "auto_confirm"
        }
    }

    // MARK: — Point d'entrée

    /// Heavy sync: refresh user, full server households list, reconcile local, ensure active, push pending.
    /// Used at login (post-auth) and at app cold start.
    static func syncAll(session: AuthSession, context: ModelContext) async throws {
        guard session.isAuthenticated else { return }

        try await session.refreshMe()
        try await session.refreshHouseholds()
        try await HouseholdMigrationService.migrateAnonymousIfNeeded(session: session, context: context)
        try reconcileServerHouseholds(session: session, context: context)
        _ = try ensureConnectedHousehold(session: session, context: context)
        try await PushService.pushPending(session: session, context: context)
        try context.save()
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSyncAt")
    }

    /// Light sync: refresh user + push pending offline ops. Used by the "Synchroniser maintenant" button.
    /// Does NOT pull server households list (handled at cold start) nor categories/recurring/transactions.
    static func quickSync(session: AuthSession, context: ModelContext) async throws {
        guard session.isAuthenticated else { return }
        try await session.refreshMe()
        try await PushService.pushPending(session: session, context: context)
        try context.save()
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSyncAt")
    }

    static func refreshBudgetLines(session: AuthSession, context: ModelContext) async throws {
        guard session.isAuthenticated, let userId = session.user?.id else { return }
        let households = try context.fetch(FetchDescriptor<Household>())
        guard let household = households.first(where: {
            $0.serverId == session.currentHousehold?.id && $0.ownerUserId == userId
        }) else { return }
        let month = Calendar.current.startOfMonth(for: .now)
        try await pullBudgetLines(household: household, month: month, context: context)
        try context.save()
    }

    // MARK: — Foyer connecté

    /// Create/update local "claimed" households from the server list.
    /// Names are reconciled (server wins). Local foyers not in the server list are left untouched
    /// (Phase 2c will flag them as orphans).
    private static func reconcileServerHouseholds(session: AuthSession, context: ModelContext) throws {
        guard let userId = session.user?.id else { return }
        let households = try context.fetch(FetchDescriptor<Household>())
        let serverIds = Set(session.serverHouseholds.map(\.id))

        // Index existing locals by serverId — covers both claimed and legacy in one pass.
        var byServerId: [Int: Household] = [:]
        for h in households where h.serverId != nil {
            if let existing = byServerId[h.serverId!] {
                // Multiple locals for same serverId → prefer the one already owned by user.
                if existing.ownerUserId != userId && h.ownerUserId == userId {
                    byServerId[h.serverId!] = h
                }
            } else {
                byServerId[h.serverId!] = h
            }
        }

        for server in session.serverHouseholds {
            if let local = byServerId[server.id] {
                local.ownerUserId = userId
                local.isAnonymous = false
                local.isOrphan = false
                local.name = server.name
                continue
            }
            let household = Household(
                serverId: server.id,
                ownerUserId: userId,
                isAnonymous: false,
                name: server.name
            )
            household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
            context.insert(household)
            byServerId[server.id] = household
        }

        for h in households where h.ownerUserId == userId && h.serverId != nil {
            h.isOrphan = !serverIds.contains(h.serverId!)
        }
        try context.save()
    }

    private static func ensureConnectedHousehold(session: AuthSession, context: ModelContext) throws -> Household {
        guard let server = session.currentHousehold, let userId = session.user?.id else {
            throw APIError.invalidResponse
        }

        let households = try context.fetch(FetchDescriptor<Household>())

        if let existing = households.first(where: { $0.serverId == server.id && $0.ownerUserId == userId }) {
            existing.name = server.name
            existing.currencyCode = server.currency
            existing.isAnonymous = false
            for h in households { h.isDefault = (h == existing) }
            return existing
        }

        if let legacy = households.first(where: { $0.serverId == server.id && $0.ownerUserId == nil }) {
            legacy.ownerUserId = userId
            legacy.isAnonymous = false
            legacy.name = server.name
            legacy.currencyCode = server.currency
            for h in households { h.isDefault = (h == legacy) }
            return legacy
        }

        let household = Household(
            serverId: server.id,
            ownerUserId: userId,
            isAnonymous: false,
            name: server.name,
            currencyCode: server.currency
        )
        household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
        context.insert(household)
        for h in households { h.isDefault = false }
        household.isDefault = true
        return household
    }

    // MARK: — Catégories (mapping serverId)

    static func pullCategories(context: ModelContext) async throws {
        struct CategoriesResponse: Decodable {
            let success: Bool
            let categories: [CategoryDTO]
        }
        struct IncomeCategoriesResponse: Decodable {
            let success: Bool
            let incomeCategories: [SubcategoryDTO]

            enum CodingKeys: String, CodingKey {
                case success
                case incomeCategories = "income_categories"
            }
        }

        let response: CategoriesResponse = try await APIClient.shared.send(
            CategoriesResponse.self, method: "GET", path: "/budget/categories"
        )

        let localCategories = try context.fetch(FetchDescriptor<Category>())
        for dto in response.categories {
            let category: Category
            if let match = localCategories.first(where: { $0.serverId == dto.id })
                ?? localCategories.first(where: { $0.serverId == nil && $0.name.lowercased() == dto.name.lowercased() }) {
                category = match
            } else {
                category = Category(name: dto.name, emoji: dto.emoji, isSystem: true)
                context.insert(category)
            }
            category.serverId = dto.id
            category.name = dto.name
            // Ne pas écraser une traduction connue (bundle) si le serveur renvoie null.
            category.nameEn = dto.nameEn ?? category.nameEn
            category.emoji = dto.emoji
            category.sortOrder = dto.sortOrder
            category.isSystem = true

            for subDTO in dto.subcategories ?? [] {
                let sub: Subcategory
                if let match = category.subcategories.first(where: { $0.serverId == subDTO.id })
                    ?? category.subcategories.first(where: { $0.serverId == nil && $0.name.lowercased() == subDTO.name.lowercased() }) {
                    sub = match
                } else {
                    sub = Subcategory(name: subDTO.name, emoji: subDTO.emoji, isSystem: true)
                    category.subcategories.append(sub)
                }
                sub.serverId = subDTO.id
                sub.name = subDTO.name
                sub.nameEn = subDTO.nameEn ?? sub.nameEn
                sub.emoji = subDTO.emoji
                sub.sortOrder = subDTO.sortOrder
                sub.isSystem = true
            }
        }

        let incomeResponse: IncomeCategoriesResponse = try await APIClient.shared.send(
            IncomeCategoriesResponse.self, method: "GET", path: "/budget/income-categories"
        )
        let localIncomeCategories = try context.fetch(FetchDescriptor<IncomeCategory>())
        for dto in incomeResponse.incomeCategories {
            let cat: IncomeCategory
            if let match = localIncomeCategories.first(where: { $0.serverId == dto.id })
                ?? localIncomeCategories.first(where: { $0.serverId == nil && $0.name.lowercased() == dto.name.lowercased() }) {
                cat = match
            } else {
                cat = IncomeCategory(name: dto.name, emoji: dto.emoji, isSystem: true)
                context.insert(cat)
            }
            cat.serverId = dto.id
            cat.name = dto.name
            cat.nameEn = dto.nameEn ?? cat.nameEn
            cat.emoji = dto.emoji
            cat.sortOrder = dto.sortOrder
            cat.isSystem = true
        }
    }

    // MARK: — Transactions du mois (serveur gagne)

    static func pullTransactions(household: Household, month: Date, context: ModelContext) async throws {
        struct TransactionsResponse: Decodable {
            let success: Bool
            let transactions: [TransactionDTO]
        }

        let response: TransactionsResponse = try await APIClient.shared.send(
            TransactionsResponse.self,
            method: "GET",
            path: "/budget/transactions",
            query: ["month": monthString(month)]
        )

        let categories = try context.fetch(FetchDescriptor<Category>())
        let incomeCategories = try context.fetch(FetchDescriptor<IncomeCategory>())

        let serverExpenseIds = Set(response.transactions.filter { $0.type == "expense" }.map(\.id))
        let serverIncomeIds = Set(response.transactions.filter { $0.type == "income" }.map(\.id))

        let localExpenses = household.expenses.filter { $0.effectiveMonth == month }
        let localIncomes = household.incomeEntries.filter { $0.effectiveMonth == month }

        for dto in response.transactions {
            guard let amount = Decimal(string: dto.amount), let date = parseDate(dto.date) else { continue }
            let status = ExpenseStatus(rawValue: dto.status) ?? .real
            let accountingMonth = dto.accountingMonth.flatMap(parseMonth)

            if dto.type == "expense" {
                let expense = localExpenses.first(where: { $0.serverId == dto.id }) ?? {
                    let new = Expense(amount: amount, label: dto.label)
                    new.serverId = dto.id
                    new.household = household
                    context.insert(new)
                    return new
                }()
                expense.amount = amount
                expense.label = dto.label
                expense.spentAt = date
                expense.accountingMonth = accountingMonth
                expense.status = status
                expense.tags = dto.tags
                expense.notes = dto.notes
                expense.category = dto.category.flatMap { ref in categories.first { $0.serverId == ref.id } }
                expense.subcategory = dto.subcategory.flatMap { ref in
                    expense.category?.subcategories.first { $0.serverId == ref.id }
                }
                expense.syncStatus = .synced
            } else if dto.type == "income" {
                let income = localIncomes.first(where: { $0.serverId == dto.id }) ?? {
                    let new = IncomeEntry(amount: amount, label: dto.label)
                    new.serverId = dto.id
                    new.household = household
                    context.insert(new)
                    return new
                }()
                income.amount = amount
                income.label = dto.label
                income.receivedAt = date
                income.accountingMonth = accountingMonth
                income.status = status
                income.notes = dto.notes
                income.incomeCategory = dto.incomeCategory.flatMap { ref in incomeCategories.first { $0.serverId == ref.id } }
                income.syncStatus = .synced
            }
        }

        for expense in localExpenses where expense.serverId != nil && !serverExpenseIds.contains(expense.serverId!) {
            context.delete(expense)
        }
        for income in localIncomes where income.serverId != nil && !serverIncomeIds.contains(income.serverId!) {
            context.delete(income)
        }
    }

    // MARK: — Lignes budgétaires du mois

    static func pullBudgetLines(household: Household, month: Date, context: ModelContext) async throws {
        struct LinesResponse: Decodable {
            let success: Bool
            let expenseLines: [BudgetLineDTO]
            let incomeLines: [BudgetLineDTO]

            enum CodingKeys: String, CodingKey {
                case success
                case expenseLines = "expense_lines"
                case incomeLines = "income_lines"
            }
        }

        let response: LinesResponse = try await APIClient.shared.send(
            LinesResponse.self,
            method: "GET",
            path: "/budget/budget",
            query: ["month": monthString(month)]
        )

        let categories = try context.fetch(FetchDescriptor<Category>())
        let incomeCategories = try context.fetch(FetchDescriptor<IncomeCategory>())

        let serverExpenseLineIds = Set(response.expenseLines.map(\.id))
        for dto in response.expenseLines {
            guard let amount = Decimal(string: dto.amount), let startMonth = parseMonth(dto.month) else { continue }
            let line = household.budgetExpenseLines.first(where: { $0.serverId == dto.id }) ?? {
                let new = BudgetExpenseLine(month: startMonth, amount: amount)
                new.serverId = dto.id
                new.household = household
                context.insert(new)
                return new
            }()
            line.month = startMonth
            line.endMonth = dto.endMonth.flatMap(parseMonth)
            line.frequency = Frequency(rawValue: dto.frequency) ?? .monthly
            line.amount = amount
            line.category = dto.category.flatMap { ref in categories.first { $0.serverId == ref.id } }
            line.subcategory = dto.subcategory.flatMap { ref in
                line.category?.subcategories.first { $0.serverId == ref.id }
            }
            line.syncStatus = .synced
        }
        for line in household.budgetExpenseLines
        where line.serverId != nil && line.isActive(for: month) && !serverExpenseLineIds.contains(line.serverId!) {
            context.delete(line)
        }

        let serverIncomeLineIds = Set(response.incomeLines.map(\.id))
        for dto in response.incomeLines {
            guard let amount = Decimal(string: dto.amount), let startMonth = parseMonth(dto.month) else { continue }
            let line = household.budgetIncomes.first(where: { $0.serverId == dto.id }) ?? {
                let new = BudgetIncome(month: startMonth, amount: amount)
                new.serverId = dto.id
                new.household = household
                context.insert(new)
                return new
            }()
            line.month = startMonth
            line.endMonth = dto.endMonth.flatMap(parseMonth)
            line.frequency = Frequency(rawValue: dto.frequency) ?? .monthly
            line.amount = amount
            line.incomeCategory = dto.incomeCategory.flatMap { ref in incomeCategories.first { $0.serverId == ref.id } }
            line.syncStatus = .synced
        }
        for line in household.budgetIncomes
        where line.serverId != nil && line.isActive(for: month) && !serverIncomeLineIds.contains(line.serverId!) {
            context.delete(line)
        }
    }

    // MARK: — Récurrents

    static func pullRecurring(household: Household, context: ModelContext) async throws {
        struct RecurringResponse: Decodable {
            let success: Bool
            let recurring: [RecurringDTO]
        }

        let response: RecurringResponse = try await APIClient.shared.send(
            RecurringResponse.self, method: "GET", path: "/budget/recurring"
        )

        let categories = try context.fetch(FetchDescriptor<Category>())
        let serverIds = Set(response.recurring.map(\.id))

        for dto in response.recurring {
            guard let amount = Decimal(string: dto.amount) else { continue }
            let template = household.recurringExpenses.first(where: { $0.serverId == dto.id }) ?? {
                let new = RecurringExpense(amount: amount, label: dto.label, dayOfMonth: dto.dayOfMonth)
                new.serverId = dto.id
                new.household = household
                context.insert(new)
                return new
            }()
            template.amount = amount
            template.label = dto.label
            template.dayOfMonth = dto.dayOfMonth
            template.isActive = dto.isActive
            template.autoConfirm = dto.autoConfirm
            template.category = dto.category.flatMap { ref in categories.first { $0.serverId == ref.id } }
            template.subcategory = dto.subcategory.flatMap { ref in
                template.category?.subcategories.first { $0.serverId == ref.id }
            }
            template.syncStatus = .synced
        }

        for template in household.recurringExpenses
        where template.serverId != nil && !serverIds.contains(template.serverId!) {
            context.delete(template)
        }
    }

    // MARK: — Helpers

    private static func monthString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }

    private static func parseDate(_ raw: String) -> Date? {
        MonthMath.parseDate(raw)
    }

    private static func parseMonth(_ raw: String) -> Date? {
        guard let utc = MonthMath.parseMonth(raw) else { return nil }
        let comps = MonthMath.calendar.dateComponents([.year, .month], from: utc)
        var local = DateComponents()
        local.year = comps.year
        local.month = comps.month
        return Calendar.current.date(from: local)
    }
}
