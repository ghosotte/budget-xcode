import Foundation
import SwiftData

@Model
public final class BudgetExpenseLine {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var household: Household?
    public var category: Category?
    public var subcategory: Subcategory?
    public var month: Date = Date.distantPast
    public var endMonth: Date?
    public var groupId: UUID = UUID()
    public var frequency: Frequency = Frequency.monthly
    public var amount: Decimal = 0
    public var syncStatus: SyncStatus = SyncStatus.local

    public init(
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

    public func isActive(for month: Date) -> Bool {
        let m = Calendar.current.startOfMonth(for: month)
        return self.month <= m && (endMonth == nil || endMonth! >= m)
    }
}

@Model
public final class BudgetIncome {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var household: Household?
    public var incomeCategory: IncomeCategory?
    public var month: Date = Date.distantPast
    public var endMonth: Date?
    public var groupId: UUID = UUID()
    public var frequency: Frequency = Frequency.monthly
    public var amount: Decimal = 0
    public var syncStatus: SyncStatus = SyncStatus.local

    public init(
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

    public func isActive(for month: Date) -> Bool {
        let m = Calendar.current.startOfMonth(for: month)
        return self.month <= m && (endMonth == nil || endMonth! >= m)
    }
}
