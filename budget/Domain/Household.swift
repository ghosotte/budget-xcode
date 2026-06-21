import Foundation
import SwiftData

@Model
final class Household {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var ownerUserId: Int?
    var isAnonymous: Bool = true
    var isOrphan: Bool = false
    var name: String = ""
    var currencyCode: String = "EUR"
    var locale: String = "fr"
    var createdAt: Date = Date.distantPast
    var isDefault: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \HouseholdMember.household)
    var members: [HouseholdMember] = []
    @Relationship(deleteRule: .cascade, inverse: \Expense.household)
    var expenses: [Expense] = []
    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.household)
    var incomeEntries: [IncomeEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetExpenseLine.household)
    var budgetExpenseLines: [BudgetExpenseLine] = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetIncome.household)
    var budgetIncomes: [BudgetIncome] = []
    @Relationship(deleteRule: .cascade, inverse: \RecurringExpense.household)
    var recurringExpenses: [RecurringExpense] = []

    init(
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
final class HouseholdMember {
    var id: UUID
    var household: Household?
    var displayName: String = ""
    var isMe: Bool = false
    var joinedAt: Date = Date.distantPast
    var serverUserId: Int?

    init(
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
