import Foundation
import SwiftData

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var household: Household?
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal = 0
    var label: String = ""
    var spentAt: Date = Date.distantPast
    var accountingMonth: Date?
    var recurringTemplate: RecurringExpense?
    var tags: [String] = []
    var notes: String?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date?
    var syncStatus: SyncStatus = SyncStatus.local

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        category: Category? = nil,
        subcategory: Subcategory? = nil,
        amount: Decimal,
        label: String,
        spentAt: Date = .now,
        accountingMonth: Date? = nil,
        recurringTemplate: RecurringExpense? = nil,
        tags: [String] = [],
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.serverId = serverId
        self.category = category
        self.subcategory = subcategory
        self.amount = amount
        self.label = label
        self.spentAt = spentAt
        self.accountingMonth = accountingMonth
        self.recurringTemplate = recurringTemplate
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }

    var effectiveMonth: Date {
        Calendar.current.startOfMonth(for: accountingMonth ?? spentAt)
    }

    var status: ExpenseStatus {
        spentAt < TransactionStatus.cutoff() ? .real : .planned
    }
}

@Model
final class IncomeEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var household: Household?
    var incomeCategory: IncomeCategory?
    var amount: Decimal = 0
    var label: String = ""
    var receivedAt: Date = Date.distantPast
    var accountingMonth: Date?
    var notes: String?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date?
    var syncStatus: SyncStatus = SyncStatus.local

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        incomeCategory: IncomeCategory? = nil,
        amount: Decimal,
        label: String,
        receivedAt: Date = .now,
        accountingMonth: Date? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.serverId = serverId
        self.incomeCategory = incomeCategory
        self.amount = amount
        self.label = label
        self.receivedAt = receivedAt
        self.accountingMonth = accountingMonth
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }

    var effectiveMonth: Date {
        Calendar.current.startOfMonth(for: accountingMonth ?? receivedAt)
    }

    var status: ExpenseStatus {
        receivedAt < TransactionStatus.cutoff() ? .real : .planned
    }
}

enum TransactionStatus {
    /// Start of tomorrow — boundary `date <= today → real`, `date > today → planned`.
    static func cutoff(now: Date = .now) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    }
}

@Model
final class RecurringExpense {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var household: Household?
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal = 0
    var label: String = ""
    var dayOfMonth: Int = 1
    var isActive: Bool = true
    var createdAt: Date = Date.distantPast
    var syncStatus: SyncStatus = SyncStatus.local

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        category: Category? = nil,
        subcategory: Subcategory? = nil,
        amount: Decimal,
        label: String,
        dayOfMonth: Int,
        isActive: Bool = true,
        createdAt: Date = .now,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.serverId = serverId
        self.category = category
        self.subcategory = subcategory
        self.amount = amount
        self.label = label
        self.dayOfMonth = min(max(dayOfMonth, 1), 28)
        self.isActive = isActive
        self.createdAt = createdAt
        self.syncStatus = syncStatus
    }
}
