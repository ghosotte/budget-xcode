import Foundation
import SwiftData

enum RecurringService {

    static func generateExpenses(for date: Date = .now, context: ModelContext) {
        let calendar = Calendar.current
        let month = calendar.startOfMonth(for: date)

        let templates = (try? context.fetch(FetchDescriptor<RecurringExpense>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []

        var didInsert = false
        for template in templates where template.isActive {
            let alreadyGenerated = expenses.contains {
                $0.recurringTemplate?.id == template.id && $0.effectiveMonth == month
            }
            guard !alreadyGenerated else { continue }

            let spentAt = calendar.date(byAdding: .day, value: template.dayOfMonth - 1, to: month)!
            let expense = Expense(
                category: template.category,
                subcategory: template.subcategory,
                amount: template.amount,
                label: template.label,
                spentAt: spentAt,
                status: template.autoConfirm ? .real : .planned,
                recurringTemplate: template
            )
            expense.household = template.household
            context.insert(expense)
            didInsert = true
        }
        if didInsert {
            try? context.save()
        }
    }
}
