import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Household.self,
            HouseholdMember.self,
            Category.self,
            Subcategory.self,
            IncomeCategory.self,
            BudgetExpenseLine.self,
            BudgetIncome.self,
            Expense.self,
            IncomeEntry.self,
            RecurringExpense.self,
        ]
    }
}

enum BudgetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
