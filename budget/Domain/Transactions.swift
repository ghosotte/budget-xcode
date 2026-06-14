import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID
    var serverId: Int?
    var household: Household?
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal = 0
    var label: String = ""
    var spentAt: Date = Date.distantPast
    var accountingMonth: Date?
    var status: ExpenseStatus = ExpenseStatus.real
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
        status: ExpenseStatus = .real,
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
        self.status = status
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
}

@Model
final class IncomeEntry {
    var id: UUID
    var serverId: Int?
    var household: Household?
    var incomeCategory: IncomeCategory?
    var amount: Decimal = 0
    var label: String = ""
    var receivedAt: Date = Date.distantPast
    var accountingMonth: Date?
    var status: ExpenseStatus = ExpenseStatus.real
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
        status: ExpenseStatus = .real,
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
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }

    var effectiveMonth: Date {
        Calendar.current.startOfMonth(for: accountingMonth ?? receivedAt)
    }
}

@Model
final class RecurringExpense {
    var id: UUID
    var serverId: Int?
    var household: Household?
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal = 0
    var label: String = ""
    var dayOfMonth: Int = 1
    var isActive: Bool = true
    var autoConfirm: Bool = false
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
        autoConfirm: Bool = false,
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
        self.autoConfirm = autoConfirm
        self.createdAt = createdAt
        self.syncStatus = syncStatus
    }
}
