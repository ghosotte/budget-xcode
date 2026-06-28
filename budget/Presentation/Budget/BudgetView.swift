import SwiftUI
import SwiftData

struct BudgetView: View {
    let month: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session
    @Query private var households: [Household]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var budgetExpenseLines: [BudgetExpenseLine]
    @Query private var budgetIncomes: [BudgetIncome]
    // Transactions scopées au mois affiché (perf RAM). Budget lines restent globales (peu nombreuses).
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]

    @State private var selectedCategory: Category?
    @State private var incomeFormTarget: IncomeLineFormTarget?

    init(month: Date) {
        self.month = month
        _expenses = Query(filter: Expense.monthPredicate(month))
        _incomeEntries = Query(filter: IncomeEntry.monthPredicate(month))
        _budgetExpenseLines = Query(filter: BudgetExpenseLine.activeMonthPredicate(month))
        _budgetIncomes = Query(filter: BudgetIncome.activeMonthPredicate(month))
    }

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    // MARK: — Données

    private var activeExpenseLines: [BudgetExpenseLine] {
        budgetExpenseLines.filter { $0.household == household && $0.isActive(for: month) }
    }

    private var activeIncomeLines: [BudgetIncome] {
        budgetIncomes.filter { $0.household == household && $0.isActive(for: month) }
    }

    private var totalBudgetExpenses: Decimal {
        activeExpenseLines.reduce(0) { $0 + $1.amount }
    }

    private var totalBudgetIncome: Decimal {
        activeIncomeLines.reduce(0) { $0 + $1.amount }
    }

    private func budget(for category: Category) -> Decimal {
        activeExpenseLines
            .filter { $0.category == category }
            .reduce(0) { $0 + $1.amount }
    }

    private func delete(_ line: BudgetIncome) {
        if PushService.isRemoteBudget(household, session: session), line.serverId != nil {
            PushService.deleteBudgetIncomeLine(line, viewMonth: month, session: session, context: modelContext)
        } else {
            BudgetLineService.delete(line, month: month, context: modelContext)
        }
    }

    private var realExpensesTotal: Decimal {
        expenses
            .filter { $0.household == household && $0.status == .real }
            .reduce(0) { $0 + $1.amount }
    }

    private var realIncomeTotal: Decimal {
        incomeEntries
            .filter { $0.household == household && $0.status == .real }
            .reduce(0) { $0 + $1.amount }
    }

    private var currentBalance: Decimal {
        realIncomeTotal - realExpensesTotal
    }

    private func spent(for category: Category) -> Decimal {
        expenses
            .filter {
                $0.household == household && $0.status == .real && $0.category == category
            }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: — Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                incomeSection
                categoryGrid
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .background(Color.budgetBg)
        .sheet(item: $selectedCategory) { category in
            CategoryBudgetDetailView(category: category, month: month)
        }
        .sheet(item: $incomeFormTarget) { target in
            BudgetIncomeLineFormView(month: month, line: target.line)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: — Synthèse

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DÉPENSES PRÉVUES")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.budgetTextMute)
                    Text(AmountFormatter.kpi(totalBudgetExpenses))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.budgetText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("REVENUS PRÉVUS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.budgetTextMute)
                    Text(AmountFormatter.kpi(totalBudgetIncome))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.budgetText)
                }
            }
            Divider().overlay(Color.budgetBorder.opacity(0.6))
            HStack {
                Text("Solde actuel")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Text(AmountFormatter.kpi(currentBalance, signed: true))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(currentBalance >= 0 ? Color.budgetPrimary : Color.budgetDanger)
            }
            HStack {
                Text("Solde prévisionnel")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Text(AmountFormatter.kpi(totalBudgetIncome - totalBudgetExpenses, signed: true))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(totalBudgetIncome - totalBudgetExpenses >= 0 ? Color.budgetPrimary : Color.budgetDanger)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: — Revenus prévus

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("REVENUS PRÉVUS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Button { incomeFormTarget = .new } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.budgetPrimary))
                }
            }

            if activeIncomeLines.isEmpty {
                Text("Aucun revenu prévu ce mois-ci.")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(activeIncomeLines) { line in
                        SwipeToDeleteRow {
                            delete(line)
                        } content: {
                            Button { incomeFormTarget = .edit(line) } label: {
                                HStack(spacing: 12) {
                                    Text(line.incomeCategory?.emoji ?? "💸")
                                        .font(.system(size: 16))
                                        .frame(width: 34, height: 34)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.budgetSurfaceMute))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(line.incomeCategory?.displayName ?? NSLocalizedString("Revenu", comment: ""))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.budgetText)
                                        Text(line.frequency.label)
                                            .font(.caption)
                                            .foregroundStyle(Color.budgetTextMute)
                                    }
                                    Spacer()
                                    Text(AmountFormatter.kpi(line.amount))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.budgetText)
                                }
                                .padding(.vertical, 9)
                            }
                        }
                        if line != activeIncomeLines.last {
                            Divider().overlay(Color.budgetBorder.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: — Grille catégories

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(categories.filter(\.isActive)) { category in
                Button { selectedCategory = category } label: {
                    CategoryBudgetCard(
                        category: category,
                        budget: budget(for: category),
                        spent: spent(for: category)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.budgetSurface)
            .stroke(Color.budgetBorder, lineWidth: 1)
    }
}

enum IncomeLineFormTarget: Identifiable {
    case new
    case edit(BudgetIncome)

    var id: String {
        switch self {
        case .new:            return "new"
        case .edit(let line): return line.id.uuidString
        }
    }

    var line: BudgetIncome? {
        if case .edit(let line) = self { return line }
        return nil
    }
}

// MARK: — Carte catégorie

private struct CategoryBudgetCard: View {
    let category: Category
    let budget: Decimal
    let spent: Decimal

    private var remaining: Decimal { budget - spent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(category.emoji)
                    .font(.system(size: 18))
                Text(category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.budgetText)
                    .lineLimit(1)
            }

            if budget > 0 {
                Text(AmountFormatter.kpi(budget))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.budgetText)
                ProgressBar(
                    ratio: ratio,
                    color: spent > budget ? .budgetDanger : .budgetPrimary
                )
                Text(remaining >= 0
                     ? "\(AmountFormatter.kpi(remaining)) restants"
                     : "\(AmountFormatter.kpi(-remaining)) de dépassement")
                    .font(.caption2)
                    .foregroundStyle(remaining >= 0 ? Color.budgetTextMute : Color.budgetDanger)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.budgetTextFaint)
                ProgressBar(ratio: 0)
                Text("Définir un budget")
                    .font(.caption2)
                    .foregroundStyle(Color.budgetTextFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.budgetSurface)
                .stroke(Color.budgetBorder, lineWidth: 1)
        )
    }

    private var ratio: Double {
        guard budget > 0 else { return 0 }
        let r = (spent as NSDecimalNumber).doubleValue / (budget as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }
}

#Preview {
    BudgetView(month: Calendar.current.startOfMonth(for: .now))
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
