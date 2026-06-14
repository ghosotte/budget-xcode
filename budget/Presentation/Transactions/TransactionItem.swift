import Foundation

enum TransactionItem: Identifiable {
    case expense(Expense)
    case income(IncomeEntry)

    var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .income(let i):  return i.id
        }
    }

    var date: Date {
        switch self {
        case .expense(let e): return e.spentAt
        case .income(let i):  return i.receivedAt
        }
    }

    var createdAt: Date {
        switch self {
        case .expense(let e): return e.createdAt
        case .income(let i):  return i.createdAt
        }
    }

    var label: String {
        switch self {
        case .expense(let e): return e.label
        case .income(let i):  return i.label
        }
    }

    var amount: Decimal {
        switch self {
        case .expense(let e): return -e.amount
        case .income(let i):  return i.amount
        }
    }

    var emoji: String {
        switch self {
        case .expense(let e):
            if let sub = e.subcategory, !sub.emoji.isEmpty { return sub.emoji }
            return e.category?.emoji ?? "📦"
        case .income(let i):
            return i.incomeCategory?.emoji ?? "💸"
        }
    }

    var categoryName: String {
        switch self {
        case .expense(let e): return e.category?.name ?? "Sans catégorie"
        case .income(let i):  return i.incomeCategory?.name ?? "Sans catégorie"
        }
    }

    var status: ExpenseStatus {
        switch self {
        case .expense(let e): return e.status
        case .income(let i):  return i.status
        }
    }

    var isIncome: Bool {
        if case .income = self { return true }
        return false
    }
}
