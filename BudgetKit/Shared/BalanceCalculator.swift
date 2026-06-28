//
//  BalanceCalculator.swift
//  budget
//
//  Calcul pur du solde actuel / prévisionnel, partagé app ↔ widget extension.
//  Extrait de DashboardView pour réutilisation sans dépendre de la vue.
//  Aligné sur le web (BudgetAppController::buildDashboardVars).
//

import Foundation

public struct BalanceResult {
    public var current: Decimal      // solde actuel = réel
    public var projected: Decimal    // solde prévisionnel
    public var realExpenses: Decimal
    public var realIncome: Decimal
    public var plannedExpenses: Decimal
    public var pendingIncome: Decimal
    public var budgetExpenses: Decimal
    public var budgetIncome: Decimal
    public var hasAnyData: Bool

    public init(
        current: Decimal,
        projected: Decimal,
        realExpenses: Decimal,
        realIncome: Decimal,
        plannedExpenses: Decimal,
        pendingIncome: Decimal,
        budgetExpenses: Decimal,
        budgetIncome: Decimal,
        hasAnyData: Bool
    ) {
        self.current = current
        self.projected = projected
        self.realExpenses = realExpenses
        self.realIncome = realIncome
        self.plannedExpenses = plannedExpenses
        self.pendingIncome = pendingIncome
        self.budgetExpenses = budgetExpenses
        self.budgetIncome = budgetIncome
        self.hasAnyData = hasAnyData
    }
}

public enum BalanceCalculator {

    /// Calcule les soldes pour un foyer sur un mois donné.
    /// Les tableaux fournis doivent être scopés au mois (cf. monthPredicate / activeMonthPredicate),
    /// le filtrage par foyer est fait ici.
    public static func compute(
        household: Household?,
        month: Date,
        expenses: [Expense],
        incomes: [IncomeEntry],
        budgetExpenseLines: [BudgetExpenseLine],
        budgetIncomes: [BudgetIncome]
    ) -> BalanceResult {
        let monthExpenses = expenses.filter { $0.household == household }
        let monthIncomes = incomes.filter { $0.household == household }
        let activeLines = budgetExpenseLines.filter { $0.household == household && $0.isActive(for: month) }
        let activeIncomeLines = budgetIncomes.filter { $0.household == household && $0.isActive(for: month) }

        let realExpenses = monthExpenses.filter { $0.status == .real }.reduce(Decimal(0)) { $0 + $1.amount }
        let realIncome = monthIncomes.filter { $0.status == .real }.reduce(Decimal(0)) { $0 + $1.amount }
        let plannedExpenses = monthExpenses.filter { $0.status == .planned }.reduce(Decimal(0)) { $0 + $1.amount }
        let pendingIncome = monthIncomes.filter { $0.status == .planned }.reduce(Decimal(0)) { $0 + $1.amount }
        let budgetExpenses = activeLines.reduce(Decimal(0)) { $0 + $1.amount }
        let budgetIncome = activeIncomeLines.reduce(Decimal(0)) { $0 + $1.amount }

        // Dépenses prévisionnelles par catégorie : max(budget, réel) + réel non-budgété.
        // Un sous-dépassement d'une catégorie ne compense pas le dépassement d'une autre.
        let budgetByCat = Dictionary(grouping: activeLines, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        let realByCat = Dictionary(grouping: monthExpenses.filter { $0.status == .real }, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        let allCategories = Set(budgetByCat.keys).union(realByCat.keys)
        let projectedExpenses = allCategories.reduce(Decimal(0)) { total, category in
            total + max(budgetByCat[category] ?? 0, realByCat[category] ?? 0)
        }

        // Revenu prévu = config budget (inclut le budgété non encaissé), borné au réel+planifié si supérieur.
        let projectedIncome = max(budgetIncome, realIncome + pendingIncome)

        let hasAnyData = !monthExpenses.isEmpty || !monthIncomes.isEmpty
            || budgetExpenses > 0 || budgetIncome > 0

        return BalanceResult(
            current: realIncome - realExpenses,
            projected: projectedIncome - projectedExpenses,
            realExpenses: realExpenses,
            realIncome: realIncome,
            plannedExpenses: plannedExpenses,
            pendingIncome: pendingIncome,
            budgetExpenses: budgetExpenses,
            budgetIncome: budgetIncome,
            hasAnyData: hasAnyData
        )
    }
}
