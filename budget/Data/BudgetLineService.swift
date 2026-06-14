import Foundation
import SwiftData

enum EditScope: String, CaseIterable {
    case thisMonthOnly
    case fromThisMonth

    var label: String {
        switch self {
        case .thisMonthOnly: return "Ce mois seulement"
        case .fromThisMonth: return "À partir de ce mois"
        }
    }
}

protocol BudgetLine: AnyObject {
    var month: Date { get set }
    var endMonth: Date? { get set }
    var groupId: UUID { get set }
    var frequency: Frequency { get set }
    var amount: Decimal { get set }
    func makeCopy(month: Date, endMonth: Date?, frequency: Frequency, amount: Decimal) -> Self
}

extension BudgetExpenseLine: BudgetLine {
    func makeCopy(month: Date, endMonth: Date?, frequency: Frequency, amount: Decimal) -> BudgetExpenseLine {
        let copy = BudgetExpenseLine(
            category: category,
            subcategory: subcategory,
            month: month,
            endMonth: endMonth,
            groupId: groupId,
            frequency: frequency,
            amount: amount
        )
        copy.household = household
        return copy
    }
}

extension BudgetIncome: BudgetLine {
    func makeCopy(month: Date, endMonth: Date?, frequency: Frequency, amount: Decimal) -> BudgetIncome {
        let copy = BudgetIncome(
            incomeCategory: incomeCategory,
            month: month,
            endMonth: endMonth,
            groupId: groupId,
            frequency: frequency,
            amount: amount
        )
        copy.household = household
        return copy
    }
}

enum BudgetLineService {

    static func needsScopeChoice(_ line: some BudgetLine, month: Date) -> Bool {
        let m = Calendar.current.startOfMonth(for: month)
        return line.month < m || line.endMonth == nil || line.endMonth! > m
    }

    static func update<L: BudgetLine & PersistentModel>(
        _ line: L,
        amount: Decimal,
        frequency: Frequency,
        scope: EditScope,
        month: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let m = calendar.startOfMonth(for: month)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: m)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: m)!
        let oldAmount = line.amount
        let oldFrequency = line.frequency
        let oldEnd = line.endMonth
        let extendsBeyond = oldEnd == nil || oldEnd! > m

        if line.month >= m {
            line.amount = amount
            line.frequency = frequency
            if scope == .thisMonthOnly && extendsBeyond {
                line.endMonth = m
                let continuation = line.makeCopy(
                    month: nextMonth, endMonth: oldEnd,
                    frequency: oldFrequency, amount: oldAmount
                )
                context.insert(continuation)
            } else if frequency == .punctual {
                line.endMonth = m
            }
        } else {
            line.endMonth = previousMonth
            switch scope {
            case .fromThisMonth:
                let endMonth = frequency == .punctual ? m : oldEnd
                let new = line.makeCopy(month: m, endMonth: endMonth, frequency: frequency, amount: amount)
                context.insert(new)
            case .thisMonthOnly:
                let new = line.makeCopy(month: m, endMonth: m, frequency: frequency, amount: amount)
                context.insert(new)
                if extendsBeyond {
                    let continuation = line.makeCopy(
                        month: nextMonth, endMonth: oldEnd,
                        frequency: oldFrequency, amount: oldAmount
                    )
                    context.insert(continuation)
                }
            }
        }
        try? context.save()
    }

    static func delete<L: BudgetLine & PersistentModel>(
        _ line: L,
        month: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let m = calendar.startOfMonth(for: month)
        if line.month >= m {
            context.delete(line)
        } else {
            line.endMonth = calendar.date(byAdding: .month, value: -1, to: m)!
        }
        try? context.save()
    }
}
