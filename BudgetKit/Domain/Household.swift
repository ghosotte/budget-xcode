import Foundation
import SwiftData

@Model
public final class Household {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var ownerUserId: Int?
    public var isAnonymous: Bool = true
    public var isOrphan: Bool = false
    public var name: String = ""
    public var currencyCode: String = "EUR"
    public var locale: String = "fr"
    public var createdAt: Date = Date.distantPast
    public var isDefault: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \HouseholdMember.household)
    public var members: [HouseholdMember] = []
    @Relationship(deleteRule: .cascade, inverse: \Expense.household)
    public var expenses: [Expense] = []
    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.household)
    public var incomeEntries: [IncomeEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetExpenseLine.household)
    public var budgetExpenseLines: [BudgetExpenseLine] = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetIncome.household)
    public var budgetIncomes: [BudgetIncome] = []
    @Relationship(deleteRule: .cascade, inverse: \RecurringExpense.household)
    public var recurringExpenses: [RecurringExpense] = []

    public init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        ownerUserId: Int? = nil,
        isAnonymous: Bool = true,
        name: String,
        currencyCode: String = "EUR",
        locale: String = "fr",
        createdAt: Date = .now,
        isDefault: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.ownerUserId = ownerUserId
        self.isAnonymous = isAnonymous
        self.name = name
        self.currencyCode = currencyCode
        self.locale = locale
        self.createdAt = createdAt
        self.isDefault = isDefault
    }
}

@Model
public final class HouseholdMember {
    public var id: UUID
    public var household: Household?
    public var displayName: String = ""
    public var isMe: Bool = false
    public var joinedAt: Date = Date.distantPast
    public var serverUserId: Int?

    public init(
        id: UUID = UUID(),
        displayName: String,
        isMe: Bool = false,
        joinedAt: Date = .now,
        serverUserId: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.isMe = isMe
        self.joinedAt = joinedAt
        self.serverUserId = serverUserId
    }
}
