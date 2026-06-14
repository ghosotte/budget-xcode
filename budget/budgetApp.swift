//
//  budgetApp.swift
//  budget
//
//  Created by Guilhem Hosotte on 05/06/2026.
//

import SwiftUI
import SwiftData

@main
struct budgetApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
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
        ])
    }
}
