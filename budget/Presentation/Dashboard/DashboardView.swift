import SwiftUI
import SwiftData

struct DashboardView: View {
    var onSeeAllExpenses: () -> Void = {}
    var onAddExpense: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session
    @State private var showRecurringList = false
    @State private var showHouseholdSwitcher = false

    @Query private var households: [Household]
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]
    @Query private var budgetExpenseLines: [BudgetExpenseLine]
    @Query private var budgetIncomes: [BudgetIncome]

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    private var currentMonth: Date {
        Calendar.current.startOfMonth(for: .now)
    }

    // MARK: — Aggregates (mois courant, foyer actif)

    private var monthExpenses: [Expense] {
        expenses.filter { $0.household == household && $0.effectiveMonth == currentMonth }
    }

    private var monthIncomes: [IncomeEntry] {
        incomeEntries.filter { $0.household == household && $0.effectiveMonth == currentMonth }
    }

    private var realExpensesTotal: Decimal {
        monthExpenses.filter { $0.status == .real }.reduce(0) { $0 + $1.amount }
    }

    private var realIncomeTotal: Decimal {
        monthIncomes.filter { $0.status == .real }.reduce(0) { $0 + $1.amount }
    }

    private var plannedExpensesTotal: Decimal {
        monthExpenses.filter { $0.status == .planned }.reduce(0) { $0 + $1.amount }
    }

    private var pendingIncomeTotal: Decimal {
        monthIncomes.filter { $0.status == .planned }.reduce(0) { $0 + $1.amount }
    }

    private var budgetExpensesTotal: Decimal {
        budgetExpenseLines
            .filter { $0.household == household && $0.isActive(for: currentMonth) }
            .reduce(0) { $0 + $1.amount }
    }

    private var budgetIncomeTotal: Decimal {
        budgetIncomes
            .filter { $0.household == household && $0.isActive(for: currentMonth) }
            .reduce(0) { $0 + $1.amount }
    }

    private var currentBalance: Decimal {
        realIncomeTotal - realExpensesTotal
    }

    // Dépenses prévisionnelles par catégorie : max(budget, réel) + réel non-budgété.
    // Aligné sur le web (BudgetAppController::buildDashboardVars) — un sous-dépassement
    // d'une catégorie ne compense pas le dépassement d'une autre.
    private var projectedExpenses: Decimal {
        let activeLines = budgetExpenseLines.filter { $0.household == household && $0.isActive(for: currentMonth) }
        let budgetByCat = Dictionary(grouping: activeLines, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        let realByCat = Dictionary(grouping: monthExpenses.filter { $0.status == .real }, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }

        let allCategories = Set(budgetByCat.keys).union(realByCat.keys)
        return allCategories.reduce(Decimal(0)) { total, category in
            total + max(budgetByCat[category] ?? 0, realByCat[category] ?? 0)
        }
    }

    private var projectedBalance: Decimal {
        // Revenu prévu = config budget (inclut le budgété non encore encaissé),
        // borné au réel+planifié si celui-ci dépasse le budget.
        let projectedIncome = max(budgetIncomeTotal, realIncomeTotal + pendingIncomeTotal)
        return projectedIncome - projectedExpenses
    }

    private var hasAnyData: Bool {
        !monthExpenses.isEmpty || !monthIncomes.isEmpty
            || budgetExpensesTotal > 0 || budgetIncomeTotal > 0
    }

    private var latestExpenses: [Expense] {
        Array(
            expenses
                .filter { $0.household == household }
                .sorted { ($0.spentAt, $0.createdAt) > ($1.spentAt, $1.createdAt) }
                .prefix(5)
        )
    }

    private var upcomingRecurring: [Expense] {
        monthExpenses
            .filter { $0.status == .planned && $0.recurringTemplate != nil }
            .sorted { $0.spentAt < $1.spentAt }
    }

    // MARK: — Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                SyncErrorBanner()
                balanceCard
                HStack(spacing: 12) {
                    expensesCard
                    incomeCard
                }
                recurringSection
                latestExpensesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(Color.budgetBg)
        .sheet(isPresented: $showRecurringList) {
            RecurringListView()
        }
        .sheet(isPresented: $showHouseholdSwitcher) {
            HouseholdSwitcherView()
        }
        .task(id: currentMonth) {
            await MonthSyncService.refreshMonth(currentMonth, session: session, context: modelContext)
        }
    }

    // MARK: — Prochains récurrents

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PROCHAINS RÉCURRENTS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Button { showRecurringList = true } label: {
                    HStack(spacing: 2) {
                        Text("Gérer")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.budgetPrimary)
                }
            }

            if upcomingRecurring.isEmpty {
                Text("Aucune dépense récurrente en attente.")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcomingRecurring) { expense in
                        HStack(spacing: 12) {
                            Text(expense.category?.emoji ?? "🔁")
                                .font(.system(size: 16))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.budgetSurfaceMute))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(expense.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.budgetText)
                                    .lineLimit(1)
                                Text("Le \(AppDateFormatter.dayMonth(expense.spentAt)) · \(AmountFormatter.full(expense.amount))")
                                    .font(.caption)
                                    .foregroundStyle(Color.budgetTextMute)
                            }
                            Spacer()
                            Button {
                                expense.status = .real
                                expense.updatedAt = .now
                                PushService.markForUpload(&expense.syncStatus, household: expense.household)
                                try? modelContext.save()
                                PushService.afterLocalChange(session: session, context: modelContext)
                            } label: {
                                Text("Confirmer")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.budgetPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.budgetPrimarySoft))
                            }
                        }
                        .padding(.vertical, 8)
                        if expense != upcomingRecurring.last {
                            Divider().overlay(Color.budgetBorder.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: — Header

    private var header: some View {
        HStack(alignment: .center) {
            Button { showHouseholdSwitcher = true } label: {
                HStack(spacing: 4) {
                    Text((household?.name ?? SeedService.defaultHouseholdName).uppercased())
                        .font(.footnote.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.budgetTextMute)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .buttonStyle(.plain)
            if household?.isAnonymous == false {
                SyncStatusBadge()
                    .padding(.leading, 6)
            }
            Spacer()
            HStack(spacing: 14) {
                Button {
                    // Recherche : à implémenter
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.budgetText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.budgetSurfaceMute))
                }
                Circle()
                    .fill(Color.budgetPrimary)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String((household?.name ?? "M").prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                    }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: — Carte Disponible

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISPONIBLE")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)

            if hasAnyData {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AmountFormatter.kpi(currentBalance, signed: true))
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(currentBalance >= 0 ? Color.budgetPrimary : Color.budgetDanger)
                        Text("Solde actuel")
                            .font(.caption)
                            .foregroundStyle(Color.budgetTextMute)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AmountFormatter.kpi(projectedBalance, signed: true))
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.budgetText)
                        Text("Prévisionnel")
                            .font(.caption)
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("——")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.budgetTextFaint)
                    Text("Budget non défini")
                        .font(.caption)
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: — Cartes Dépenses / Revenus

    private var expensesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DÉPENSES")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)
            Text(AmountFormatter.kpi(realExpensesTotal))
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Color.budgetText)
            ProgressBar(
                ratio: ratio(realExpensesTotal, of: budgetExpensesTotal),
                color: .budgetPrimary
            )
            Group {
                if budgetExpensesTotal > 0 {
                    Text("\(AmountFormatter.kpi(budgetExpensesTotal - realExpensesTotal)) restants")
                        .foregroundStyle(Color.budgetTextMute)
                } else {
                    Text(AppDateFormatter.monthYear(currentMonth))
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var incomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REVENUS")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)
            Text(AmountFormatter.kpi(realIncomeTotal))
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Color.budgetText)
            ProgressBar(
                ratio: ratio(realIncomeTotal, of: max(budgetIncomeTotal, realIncomeTotal + pendingIncomeTotal)),
                color: .budgetPrimary
            )
            Group {
                if pendingIncomeTotal > 0 {
                    Text("\(AmountFormatter.kpi(pendingIncomeTotal, signed: true)) en attente")
                        .foregroundStyle(Color.budgetAccent)
                } else {
                    Text(AppDateFormatter.monthYear(currentMonth))
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private func ratio(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        let r = (value as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }

    // MARK: — Dernières dépenses

    private var latestExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dernières dépenses")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Color.budgetText)
                Spacer()
                if !latestExpenses.isEmpty {
                    Button(action: onSeeAllExpenses) {
                        HStack(spacing: 2) {
                            Text("Tout voir")
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.budgetPrimary)
                    }
                }
            }

            if latestExpenses.isEmpty {
                emptyExpensesState
            } else {
                VStack(spacing: 0) {
                    ForEach(latestExpenses) { expense in
                        ExpenseRow(expense: expense)
                        if expense != latestExpenses.last {
                            Divider().overlay(Color.budgetBorder.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(cardBackground)
            }
        }
        .padding(.top, 8)
    }

    private var emptyExpensesState: some View {
        VStack(spacing: 12) {
            Text("📭")
                .font(.system(size: 40))
            Text("Aucune dépense pour l'instant.")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
            Button(action: onAddExpense) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ajouter la première")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.budgetPrimary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.budgetSurface)
            .stroke(Color.budgetBorder, lineWidth: 1)
    }
}

// MARK: — Ligne de dépense

private struct ExpenseRow: View {
    let expense: Expense

    private var emoji: String {
        if let sub = expense.subcategory, !sub.emoji.isEmpty { return sub.emoji }
        return expense.category?.emoji ?? "📦"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.budgetText)
                    .lineLimit(1)
                Text("\(AppDateFormatter.dayMonth(expense.spentAt)) · \(expense.category?.name ?? "Sans catégorie")")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
            }

            Spacer()

            Text(AmountFormatter.full(expense.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.budgetText)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
