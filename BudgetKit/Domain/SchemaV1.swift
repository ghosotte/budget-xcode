import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
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

public enum BudgetMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
