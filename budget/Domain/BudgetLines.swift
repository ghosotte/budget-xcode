import Foundation
import SwiftData

@Model
final class BudgetExpenseLine {
    var id: UUID
    var serverId: Int?
    var household: Household?
    var category: Category?
    var subcategory: Subcategory?
    var month: Date = Date.distantPast
    var endMonth: Date?
    var groupId: UUID = UUID()
    var frequency: Frequency = Frequency.monthly
    var amount: Decimal = 0
    var syncStatus: SyncStatus = SyncStatus.local

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        category: Category? = nil,
        subcategory: Subcategory? = nil,
        month: Date,
        endMonth: Date? = nil,
        groupId: UUID = UUID(),
        frequency: Frequency = .monthly,
        amount: Decimal,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.serverId = serverId
        self.category = category
        self.subcategory = subcategory
        self.month = month
        self.endMonth = endMonth
        self.groupId = groupId
        self.frequency = frequency
        self.amount = amount
        self.syncStatus = syncStatus
    }

    func isActive(for month: Date) -> Bool {
        let m = Calendar.current.startOfMonth(for: month)
        return self.month <= m && (endMonth == nil || endMonth! >= m)
    }
}

@Model
final class BudgetIncome {
    var id: UUID
    var serverId: Int?
    var household: Household?
    var incomeCategory: IncomeCategory?
    var month: Date = Date.distantPast
    var endMonth: Date?
    var groupId: UUID = UUID()
    var frequency: Frequency = Frequency.monthly
    var amount: Decimal = 0
    var syncStatus: SyncStatus = SyncStatus.local

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        incomeCategory: IncomeCategory? = nil,
        month: Date,
        endMonth: Date? = nil,
        groupId: UUID = UUID(),
        frequency: Frequency = .monthly,
        amount: Decimal,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.serverId = serverId
        self.incomeCategory = incomeCategory
        self.month = month
        self.endMonth = endMonth
        self.groupId = groupId
        self.frequency = frequency
        self.amount = amount
        self.syncStatus = syncStatus
    }

    func isActive(for month: Date) -> Bool {
        let m = Calendar.current.startOfMonth(for: month)
        return self.month <= m && (endMonth == nil || endMonth! >= m)
    }
}
