import Foundation
import SwiftData

@Model
public final class Expense {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var household: Household?
    public var category: Category?
    public var subcategory: Subcategory?
    public var amount: Decimal = 0
    public var label: String = ""
    public var spentAt: Date = Date.distantPast
    public var accountingMonth: Date?
    public var recurringTemplate: RecurringExpense?
    public var tags: [String] = []
    public var notes: String?
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date?
    public var syncStatus: SyncStatus = SyncStatus.local

    /// Mois comptable dénormalisé (début de mois) = `accountingMonth ?? spentAt`. Stocké pour que
    /// les `@Query` filtrent côté SQLite par mois (perf mémoire) sans charger tout l'historique.
    /// Maintenu via `refreshEffectiveMonth()` à chaque écriture de `spentAt`/`accountingMonth`.
    /// Défaut `.distantPast` : backfill au cold start (voir `EffectiveMonthBackfill`).
    public var effectiveMonth: Date = Date.distantPast

    public init(
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
        self.effectiveMonth = Calendar.current.startOfMonth(for: accountingMonth ?? spentAt)
    }

    /// Recalcule `effectiveMonth`. À appeler après toute mutation de `spentAt` ou `accountingMonth`.
    public func refreshEffectiveMonth() {
        effectiveMonth = Calendar.current.startOfMonth(for: accountingMonth ?? spentAt)
    }

    public var status: ExpenseStatus {
        spentAt < TransactionStatus.cutoff() ? .real : .planned
    }
}

@Model
public final class IncomeEntry {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var household: Household?
    public var incomeCategory: IncomeCategory?
    public var amount: Decimal = 0
    public var label: String = ""
    public var receivedAt: Date = Date.distantPast
    public var accountingMonth: Date?
    public var notes: String?
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date?
    public var syncStatus: SyncStatus = SyncStatus.local

    /// Mois comptable dénormalisé (début de mois) = `accountingMonth ?? receivedAt`. Voir `Expense.effectiveMonth`.
    public var effectiveMonth: Date = Date.distantPast

    public init(
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
        self.effectiveMonth = Calendar.current.startOfMonth(for: accountingMonth ?? receivedAt)
    }

    /// Recalcule `effectiveMonth`. À appeler après toute mutation de `receivedAt` ou `accountingMonth`.
    public func refreshEffectiveMonth() {
        effectiveMonth = Calendar.current.startOfMonth(for: accountingMonth ?? receivedAt)
    }

    public var status: ExpenseStatus {
        receivedAt < TransactionStatus.cutoff() ? .real : .planned
    }
}

public enum TransactionStatus {
    /// Start of tomorrow — boundary `date <= today → real`, `date > today → planned`.
    public static func cutoff(now: Date = .now) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    }
}

@Model
public final class RecurringExpense {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var household: Household?
    public var category: Category?
    public var subcategory: Subcategory?
    public var amount: Decimal = 0
    public var label: String = ""
    public var dayOfMonth: Int = 1
    public var isActive: Bool = true
    public var createdAt: Date = Date.distantPast
    public var syncStatus: SyncStatus = SyncStatus.local

    public init(
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
